#!/usr/bin/env python3
"""Check real MDB I/O pages using the already-built tabled_read fixture."""
import argparse
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--mdb', default='mdb')
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True,
                        help='new, exclusively owned artifact directory')
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--quiet-on-success', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    output = args.output.resolve()
    transcript = bytearray()
    pending = bytearray()
    exchanges = []
    commands = []
    failures = []
    process = None
    chunks = queue.Queue()
    reader = None
    deadline = time.monotonic() + args.timeout
    result = {'status': 'failed', 'checks': [], 'failures': failures}

    def remaining():
        seconds = deadline - time.monotonic()
        if seconds <= 0:
            raise RuntimeError('deadline expired waiting for MDB')
        return seconds

    # select() cannot monitor subprocess pipes on all hosts.
    def read_stdout():
        try:
            while True:
                chunk = os.read(process.stdout.fileno(), 65536)
                chunks.put(chunk)
                if not chunk:
                    return
        except (OSError, ValueError) as error:
            chunks.put(error)

    def read_chunk():
        try:
            chunk = chunks.get(timeout=remaining())
        except queue.Empty:
            raise RuntimeError('deadline expired waiting for MDB output')
        if isinstance(chunk, Exception):
            raise chunk
        transcript.extend(chunk)
        return chunk

    def read_until_prompt():
        while True:
            at = pending.find(b'mdb> ')
            if at >= 0:
                response = bytes(pending[:at])
                del pending[:at + len(b'mdb> ')]
                return response.decode('utf-8', errors='replace')
            chunk = read_chunk()
            if not chunk:
                raise RuntimeError('MDB exited before the next prompt')
            pending.extend(chunk)

    def send(command):
        commands.append(command)
        exchanges.append({'command': command, 'response': None})
        process.stdin.write((command + '\n').encode())
        process.stdin.flush()
        response = read_until_prompt()
        exchanges[-1]['response'] = response
        return response

    def check(label, observed, expected):
        passed = observed == expected
        result['checks'].append({'claim': label, 'observed': observed,
                                 'expected': expected, 'passed': passed})
        if not passed:
            failures.append(label + ': expected ' + repr(expected)
                            + ', observed ' + repr(observed))

    def stats(response):
        pairs = re.findall(r'^\s*(phase|counter|hwm|start|end)\s*=\s*(\d+)\s*$',
                           response, re.MULTILINE)
        if len(pairs) != 5 or len(dict(pairs)) != 5:
            raise RuntimeError('missing or duplicate I/O table state: ' + response)
        return {key: int(value) for key, value in pairs}

    def actions(response):
        parsed = []
        for line in response.splitlines():
            if not re.match(r'^\s*action\s+\d+\s*:', line):
                continue
            match = re.fullmatch(r'\s*action\s+(\d+):\s*(.*?)\s*', line)
            action_id = int(match[1])
            payload = match[2]
            opened = re.fullmatch(
                r'open_input\("tabled_read\.data",\s*0,\s*c_pointer\((0x[0-9A-Fa-f]+)\)\)',
                payload)
            read = re.fullmatch(
                r'read_char_code\(c_pointer\((0x[0-9A-Fa-f]+)\),\s*(-?\d+)\)', payload)
            if opened:
                parsed.append({'id': action_id, 'operation': 'open_input',
                               'file': 'tabled_read.data', 'result': 0,
                               'stream': int(opened[1], 16)})
            elif read:
                parsed.append({'id': action_id, 'operation': 'read_char_code',
                               'stream': int(read[1], 16), 'code': int(read[2])})
            else:
                raise RuntimeError('incomplete or unexpected I/O action: ' + line)
        return parsed

    try:
        executable = args.executable.resolve(strict=True)
        mdb_command = shutil.which(args.mdb)
        if mdb_command is None:
            raise RuntimeError('cannot find debugger: ' + args.mdb)
        mdb = Path(mdb_command).resolve(strict=True)
        data = (args.data_dir / 'tabled_read.data').resolve(strict=True)
        first_record = data.read_bytes().splitlines(keepends=True)[0]
        if not re.fullmatch(rb'[0-9]+\n', first_record):
            raise RuntimeError('first record must be decimal digits followed by LF')
        expected_hwm = 1 + len(first_record)
        work = output / 'work'
        work.mkdir()
        shutil.copyfile(data, work / 'tabled_read.data')
        environment = os.environ.copy()
        # Like MDB_NOINIT, do not depend on a workspace or personal mdbrc.
        environment.update(HOME='/nonexistent', MERCURY_SUPPRESS_MDB_BANNER='yes',
                           MERCURY_DEBUGGER_INIT='', MERCURY_OPTIONS='-de')
        command = [str(mdb), str(executable)]
        result.update(command=command, cwd=str(work),
                      expected_read_codes=list(first_record))
        process = subprocess.Popen(command, cwd=work, env=environment,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, bufsize=0)
        reader = threading.Thread(target=read_stdout, daemon=True)
        reader.start()
        read_until_prompt()
        for command in ('echo on', 'register --quiet', 'scroll off', 'context none',
                        'table_io allow', 'break tabled_read__test', 'table_io start'):
            send(command)
        called = send('continue')
        if not re.search(r'\bCALL pred tabled_read\.test/5-0\b', called):
            raise RuntimeError('did not stop at the first tabled_read.test CALL')
        finished = send('finish -n')
        if not re.search(r'\bEXIT pred tabled_read\.test/5-0\b', finished):
            raise RuntimeError('did not complete the first tabled_read.test frame')
        frame = send('print -f *')
        for name, value in (('SoFar', 0), ('N', int(first_record))):
            found = re.findall(r'^\s*' + name + r'\s+\(arg \d+\)\s+(-?\d+)\s*$',
                               frame, re.MULTILINE)
            check('completed frame ' + name, [int(item) for item in found], [value])
        initial = stats(send('table_io stats'))
        check('recorded table at first completed frame',
              {key: initial[key] for key in ('counter', 'hwm', 'start')},
              {'counter': expected_hwm, 'hwm': expected_hwm, 'start': 0})
        # Derive the maximum from the inferior's live unbounded-end sentinel,
        # not Python's or the host C compiler's pointer/long width.
        wordmax = initial['end']
        if wordmax <= expected_hwm or wordmax & (wordmax + 1):
            raise RuntimeError('table end is not an unsigned-word maximum sentinel')
        result.update(runtime_unsigned_max=wordmax, initial_stats=initial)

        streams = re.findall(
            r'^\s*Stream\s+\(arg \d+\)\s+c_pointer\((0x[0-9A-Fa-f]+)\)\s*$',
            frame, re.MULTILINE)
        if len(streams) != 1 or int(streams[0], 16) == 0:
            raise RuntimeError('completed frame does not expose its open stream')
        stream = int(streams[0], 16)
        expected = [{'id': 0, 'operation': 'open_input', 'file': 'tabled_read.data',
                     'result': 0, 'stream': stream}]
        expected.extend({'id': index, 'operation': 'read_char_code', 'stream': stream,
                         'code': code} for index, code in enumerate(first_record, 1))
        first = actions(send('print -f -m 1 io'))
        check('one-action page complete open payload', first, expected[:1])
        rest = actions(send('print -f -m ' + str(wordmax) + ' io'))
        check('maximum page resumes with all remaining IDs and payloads', rest, expected[1:])
        check('next command succeeds without changing recording',
              stats(send('table_io stats')), initial)

        # N+1 available versus bound N is the star branch's distinct boundary.
        finite = actions(send('print -f -m ' + str(expected_hwm - 1) + ' io *'))
        check('star N+1 boundary prints exactly N actions', finite, expected[:-1])
        all_actions = actions(send('print -f -m ' + str(wordmax) + ' io *'))
        check('star maximum includes all complete actions', all_actions, expected)
        check('final recorded state is unchanged', stats(send('table_io stats')), initial)

        commands.append('quit -y')
        exchanges.append({'command': 'quit -y', 'response': None})
        process.stdin.write(b'quit -y\n')
        process.stdin.flush()
        process.stdin.close()
        final = bytearray(pending)
        pending.clear()
        while True:
            chunk = read_chunk()
            if not chunk:
                break
            final.extend(chunk)
        exchanges[-1]['response'] = final.decode('utf-8', errors='replace')
        result['returncode'] = process.wait(timeout=remaining())
        check('clean debugger quit', result['returncode'], 0)
        if not failures:
            result['status'] = 'passed'
    except Exception as error:
        failures.append(str(error))
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
            process.wait()
            result['returncode'] = process.returncode
            if reader is not None:
                reader.join(timeout=1)
            process.stdout.close()
            if not process.stdin.closed:
                process.stdin.close()
        (output / 'mdb.raw').write_bytes(transcript)
        (output / 'commands.inp').write_text('\n'.join(commands) + '\n')
        (output / 'exchanges.json').write_text(json.dumps(exchanges, indent=2) + '\n')
        (output / 'observed.json').write_text(json.dumps(result, indent=2) + '\n')
    if result['status'] != 'passed' or not args.quiet_on_success:
        print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
