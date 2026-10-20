%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%
%
% Typeinfo liveness requires the evidence for an existential payload at debug
% events even if the program only uses that payload through its packaged
% closure. LLDS deconstruction used to discard that evidence as a local,
% unused field, leaving the stack-saving code with no value to save.
%
% Keep the producer and consumer separate so specialization and inlining do
% not remove the existential deconstruction. Exercise two payload types,
% explicit generic evidence use (an adjacent working case), an explicitly
% moded predicate closure, and both outcomes of a semidet deconstruction.
%
%---------------------------------------------------------------------------%

:- module existential_render.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module list.
:- import_module string.

:- type command
    --->    some [T] command(T, func(T) = string).

:- func make_integer = command.
:- pragma no_inline(make_integer/0).

make_integer = 'new command'(42, string.int_to_string).

:- func make_string = command.
:- pragma no_inline(make_string/0).

make_string = 'new command'("abcd", (func(S) = S)).

:- func execute(command) = string.
:- pragma no_inline(execute/1).

execute(C) = Render(X) :-
    C = command(X, Render).

:- func execute_with_evidence(command) = string.
:- pragma no_inline(execute_with_evidence/1).

execute_with_evidence(C) = string.string(X) ++ ":" ++ Render(X) :-
    C = command(X, Render).

:- type action
    --->    some [T] action(T, pred(T::in, string::out) is det).

:- func make_action(string) = action.
:- pragma no_inline(make_action/1).

make_action(Prefix) = 'new action'("abcd",
    (pred(S::in, R::out) is det :- R = Prefix ++ S)).

:- pred execute_action(action::in, string::out) is det.
:- pragma no_inline(execute_action/2).

execute_action(A, Result) :-
    A = action(X, Render),
    Render(X, Result).

:- type optional_command
    --->    some [T] available(T, func(T) = string)
    ;       unavailable.

:- func make_optional = optional_command.
:- pragma no_inline(make_optional/0).

make_optional = 'new available'(42, string.int_to_string).

:- pred try_execute(optional_command::in, string::out) is semidet.
:- pragma no_inline(try_execute/2).

try_execute(C, Result) :-
    C = available(X, Render),
    Result = Render(X).

:- func execute_optional(optional_command) = string.
:- pragma no_inline(execute_optional/1).

execute_optional(C) = Result :-
    ( if try_execute(C, Rendered) then
        Result = Rendered
    else
        Result = "missing"
    ).

main(!IO) :-
    execute_action(make_action("prefix:"), ActionResult),
    io.format("integer=%s; string=%s\n",
        [s(execute(make_integer)), s(execute(make_string))], !IO),
    io.format("explicit=%s; predicate=%s\n",
        [s(execute_with_evidence(make_integer)), s(ActionResult)], !IO),
    io.format("present=%s; absent=%s\n",
        [s(execute_optional(make_optional)),
        s(execute_optional(unavailable))], !IO).
