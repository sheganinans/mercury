%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et wm=0 tw=0
%---------------------------------------------------------------------------%
% Copyright (C) 1994-2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
% 
% File: term_io.m.
% Main author: fjh.
% Stability: medium to high.
% 
% This file encapsulates all the term I/O.
% This exports predicates to read and write terms in the
% nice ground representation provided in term.m.
% 
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module term_io.
:- interface.

:- import_module char.
:- import_module io.
:- import_module ops.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

% External interface: exported predicates

% The following are not yet implemented.
%
% :- type op_type ---> fx; fy; xf; yf; xfx; xfy; yfx; fxx; fxy; fyx; fyy.
%
%   % term_io.op(Prec, Type, OpName, !IO):
%   % Define an operator as per Prolog op/3 for future calls
%   % to term_io.read_term.
% :- pred term_io.op(int::in, op_type::in, string::in, io::di, io::uo) is det.
%
% :- type op_details ---> op(int, op_type, string).
%
%   % Return a list containing all the current operator definitions.
%   % Does not modify the io.state.
% :- pred term_io.current_ops(list(op_details)::out, io::di, io::uo) is det.

:- type read_term(T) ---> eof ; error(string, int) ; term(varset(T), term(T)).

:- type read_term   == read_term(generic).

    % term_io.read_term(Result, !IO):
    %
    % Read a term from standard input. Similar to NU-Prolog read_term/2,
    % except that resulting term is in the ground representation.
    % Binds Result to either `eof', `term(VarSet, Term)', or
    % `error(Message, LineNumber)'.
    %
:- pred term_io.read_term(read_term(T)::out, io::di, io::uo) is det.

    % As above, except uses the given operator table instead of
    % the standard Mercury operators.
    %
:- pred term_io.read_term_with_op_table(Ops::in, read_term(T)::out,
    io::di, io::uo) is det <= op_table(Ops).

    % Writes a term to standard output. Uses the variable names specified
    % by the varset. Writes _N for all unnamed variables, with N starting at 0.
    %
:- pred term_io.write_term(varset(T)::in, term(T)::in, io::di, io::uo) is det.

    % As above, except uses the given operator table instead of the
    % standard Mercury operators.
    %
:- pred term_io.write_term_with_op_table(Ops::in, varset(T)::in, term(T)::in,
    io::di, io::uo) is det <= op_table(Ops).

    % As above, except it appends a period and new-line.
    %
:- pred term_io.write_term_nl(varset(T)::in, term(T)::in, io::di, io::uo)
    is det.

    % As above, except it appends a period and new-line.
    %
:- pred term_io.write_term_nl_with_op_table(Ops::in, varset(T)::in,
    term(T)::in, io::di, io::uo) is det <= op_table(Ops).

    % Writes a constant (integer, float, string, or atom) to stdout.
    %
:- pred term_io.write_constant(const::in, io::di, io::uo) is det.

    % Like term_io.write_constant, but return the result in a string.
    %
:- func term_io.format_constant(const) = string.

    % Writes a variable to stdout.
    %
:- pred term_io.write_variable(var(T)::in, varset(T)::in, io::di, io::uo)
    is det.

    % As above, except uses the given operator table instead of the
    % standard Mercury operators.
    %
:- pred term_io.write_variable_with_op_table(Ops::in, var(T)::in,
    varset(T)::in, io::di, io::uo) is det <= op_table(Ops).

    % Given a string S, write S in double-quotes, with characters
    % escaped if necessary, to stdout.
    %
:- pred term_io.quote_string(string::in, io::di, io::uo) is det.

    % Like term_io.quote_string, but return the result in a string.
    %
:- func term_io.quoted_string(string) = string.

    % Given an atom-name A, write A, enclosed in single-quotes if necessary,
    % with characters escaped if necessary, to stdout.
    %
:- pred term_io.quote_atom(string::in, io::di, io::uo) is det.

    % Like term_io.quote_atom, but return the result in a string.
    %
:- func term_io.quoted_atom(string) = string.

    % Given a character C, write C in single-quotes,
    % escaped if necessary, to stdout.
    %
:- pred term_io.quote_char(char::in, io::di, io::uo) is det.

    % Like term_io.quote_char, but return the result in a string.
    %
:- func term_io.quoted_char(char) = string.

    % Given a character C, write C, escaped if necessary, to stdout.
    % The character is not enclosed in quotes.
    %
:- pred term_io.write_escaped_char(char::in, io::di, io::uo) is det.

    % Like term_io.write_escaped_char, but return the result in a string.
    %
:- func term_io.escaped_char(char) = string.

    % Given a string S, write S, with characters escaped if necessary,
    % to stdout. The string is not enclosed in quotes.
    %
:- pred term_io.write_escaped_string(string::in, io::di, io::uo) is det.

    % Like term_io.write_escaped_char, but return the result in a string.
    %
:- func term_io.escaped_string(string) = string.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

% Everything below here is not intended to be part of the public interface,
% and will not be included in the Mercury library reference manual.

%-----------------------------------------------------------------------------%
:- interface.

    % for use by io.m.

:- type adjacent_to_graphic_token
    --->    maybe_adjacent_to_graphic_token
    ;       not_adjacent_to_graphic_token.

:- pred term_io.quote_atom(string::in, adjacent_to_graphic_token::in,
    io::di, io::uo) is det.

:- func term_io.quoted_atom(string, adjacent_to_graphic_token) = string.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module bool.
:- import_module char.
:- import_module int.
:- import_module lexer.
:- import_module list.
:- import_module parser.
:- import_module require.
:- import_module string.

%-----------------------------------------------------------------------------%

term_io.read_term(Result, !IO) :-
    io.get_op_table(Ops, !IO),
    term_io.read_term_with_op_table(Ops, Result, !IO).

term_io.read_term_with_op_table(Ops, Result, !IO) :-
    parser.read_term_with_op_table(Ops, Result, !IO).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

    % write a variable to standard output.
    %
    % There are two ways we could choose to write unnamed variables
    % (ie `_'):
    %   Convert the variable to an integer representation and write
    %   `_N' where N is that integer representation. This has the
    %   advantage that such variables get printed in a cannonical
    %   way, so rearranging terms containing such variables will
    %   not effect the way they are numbered (this includes breaking
    %   up a term and printing the pieces separately).
    % or
    %   Number the unnamed variables from 0 and write `_N' where
    %   N is the number in the sequence of such variables. This has
    %   the advantage that such variables can be visually scanned
    %   rather more easily (for example in error messages).
    %
    % An ideal solution would be to provide both, and a flag to choose
    % between the two. At the moment we provide only the first, though
    % the infrastructure for the second is present in the code.

term_io.write_variable(Variable, VarSet, !IO) :-
    io.get_op_table(Ops, !IO),
    term_io.write_variable_with_op_table(Ops, Variable, VarSet, !IO).

term_io.write_variable_with_op_table(Ops, Variable, VarSet, !IO) :-
    term_io.write_variable_2(Ops, Variable, VarSet, _, 0, _, !IO).

:- pred term_io.write_variable_2(Ops::in, var(T)::in,
    varset(T)::in, varset(T)::out, int::in, int::out,
    io::di, io::uo) is det <= op_table(Ops).

term_io.write_variable_2(Ops, Id, !VarSet, !N, !IO) :-
    ( varset.search_var(!.VarSet, Id, Val) ->
        term_io.write_term_2(Ops, Val, !VarSet, !N, !IO)
    ; varset.search_name(!.VarSet, Id, Name) ->
        io.write_string(Name, !IO)
    ;
        % XXX Problems with name clashes.

        term.var_to_int(Id, VarNum),
        string.int_to_string(VarNum, Num),
        string.append("_", Num, VarName),
        varset.name_var(!.VarSet, Id, VarName, !:VarSet),
        !:N = !.N + 1,
        io.write_string(VarName, !IO)
    ).

%-----------------------------------------------------------------------------%

term_io.write_term(VarSet, Term, !IO) :-
    io.get_op_table(Ops, !IO),
    term_io.write_term_with_op_table(Ops, VarSet, Term, !IO).

term_io.write_term_with_op_table(Ops, VarSet, Term, !IO) :-
    term_io.write_term_2(Ops, Term, VarSet, _, 0, _, !IO).

:- pred term_io.write_term_2(Ops::in, term(T)::in,
    varset(T)::in, varset(T)::out, int::in, int::out, io::di, io::uo) is det
    <= op_table(Ops).

term_io.write_term_2(Ops, Term, !VarSet, !N, !IO) :-
    term_io.write_term_3(Ops, Term, ops.max_priority(Ops) + 1,
        !VarSet, !N, !IO).

:- pred term_io.write_arg_term(Ops::in, term(T)::in,
    varset(T)::in, varset(T)::out, int::in, int::out, io::di, io::uo) is det
    <= op_table(Ops).

term_io.write_arg_term(Ops, Term, !VarSet, !N, !IO) :-
    term_io.write_term_3(Ops, Term, ops.arg_priority(Ops),
        !VarSet, !N, !IO).

:- pred term_io.write_term_3(Ops::in, term(T)::in, ops.priority::in,
    varset(T)::in, varset(T)::out, int::in, int::out,
    io::di, io::uo) is det <= op_table(Ops).

term_io.write_term_3(Ops, term.variable(Id), _, !VarSet, !N, !IO) :-
    term_io.write_variable_2(Ops, Id, !VarSet, !N, !IO).
term_io.write_term_3(Ops, term.functor(Functor, Args, _), Priority,
        !VarSet, !N, !IO) :-
    (
        Functor = term.atom("[|]"),
        Args = [ListHead, ListTail]
    ->
        io.write_char('[', !IO),
        term_io.write_arg_term(Ops, ListHead, !VarSet, !N, !IO),
        term_io.write_list_tail(Ops, ListTail, !VarSet, !N, !IO),
        io.write_char(']', !IO)
    ;
        Functor = term.atom("[]"),
        Args = []
    ->
        io.write_string("[]", !IO)
    ;
        Functor = term.atom("{}"),
        Args = [BracedTerm]
    ->
        io.write_string("{ ", !IO),
        term_io.write_term_2(Ops, BracedTerm, !VarSet, !N, !IO),
        io.write_string(" }", !IO)
    ;
        Functor = term.atom("{}"),
        Args = [BracedHead | BracedTail]
    ->
        io.write_char('{', !IO),
        term_io.write_arg_term(Ops, BracedHead, !VarSet, !N, !IO),
        term_io.write_term_args(Ops, BracedTail, !VarSet, !N, !IO),
        io.write_char('}', !IO)
    ;
        % The empty functor '' is used for higher-order syntax: Var(Arg, ...)
        % gets parsed as ''(Var, Arg). When writing it out, we want to use
        % the nice syntax.
        Functor = term.atom(""),
        Args = [term.variable(Var), FirstArg | OtherArgs]
    ->
        term_io.write_variable_2(Ops, Var, !VarSet, !N, !IO),
        io.write_char('(', !IO),
        term_io.write_arg_term(Ops, FirstArg, !VarSet, !N, !IO),
        term_io.write_term_args(Ops, OtherArgs, !VarSet, !N, !IO),
        io.write_char(')', !IO)
    ;
        Args = [PrefixArg],
        Functor = term.atom(OpName),
        ops.lookup_prefix_op(Ops, OpName, OpPriority, OpAssoc)
    ->
        maybe_write_paren('(', Priority, OpPriority, !IO),
        term_io.write_constant(Functor, !IO),
        io.write_char(' ', !IO),
        adjust_priority_for_assoc(OpPriority, OpAssoc, NewPriority),
        term_io.write_term_3(Ops, PrefixArg, NewPriority, !VarSet, !N, !IO),
        maybe_write_paren(')', Priority, OpPriority, !IO)
    ;
        Args = [PostfixArg],
        Functor = term.atom(OpName),
        ops.lookup_postfix_op(Ops, OpName, OpPriority, OpAssoc)
    ->
        maybe_write_paren('(', Priority, OpPriority, !IO),
        adjust_priority_for_assoc(OpPriority, OpAssoc, NewPriority),
        term_io.write_term_3(Ops, PostfixArg, NewPriority, !VarSet, !N, !IO),
        io.write_char(' ', !IO),
        term_io.write_constant(Functor, !IO),
        maybe_write_paren(')', Priority, OpPriority, !IO)
    ;
        Args = [Arg1, Arg2],
        Functor = term.atom(OpName),
        ops.lookup_infix_op(Ops, OpName, OpPriority, LeftAssoc, RightAssoc)
    ->
        maybe_write_paren('(', Priority, OpPriority, !IO),
        adjust_priority_for_assoc(OpPriority, LeftAssoc, LeftPriority),
        term_io.write_term_3(Ops, Arg1, LeftPriority, !VarSet, !N, !IO),
        ( OpName = "," ->
            io.write_string(", ", !IO)
        ; OpName = "." ->
            % If the operator is '.'/2 then we must not put spaces around it
            % (or at the very least, we should not put spaces afterwards, which
            % would make it appear as the end-of-term token). However, we do
            % have to quote it if the right hand side can begin with a digit.
            ( starts_with_digit(Arg2) ->
                Dot = "'.'"
            ;
                Dot = "."
            ),
            io.write_string(Dot, !IO)
        ;
            io.write_char(' ', !IO),
            term_io.write_constant(Functor, !IO),
            io.write_char(' ', !IO)
        ),
        adjust_priority_for_assoc(OpPriority, RightAssoc, RightPriority),
        term_io.write_term_3(Ops, Arg2, RightPriority, !VarSet, !N, !IO),
        maybe_write_paren(')', Priority, OpPriority, !IO)
    ;
        Args = [Arg1, Arg2],
        Functor = term.atom(OpName),
        ops.lookup_binary_prefix_op(Ops, OpName, OpPriority,
            FirstAssoc, SecondAssoc)
    ->
        maybe_write_paren('(', Priority, OpPriority, !IO),
        term_io.write_constant(Functor, !IO),
        io.write_char(' ', !IO),
        adjust_priority_for_assoc(OpPriority, FirstAssoc, FirstPriority),
        term_io.write_term_3(Ops, Arg1, FirstPriority, !VarSet, !N, !IO),
        io.write_char(' ', !IO),
        adjust_priority_for_assoc(OpPriority, SecondAssoc, SecondPriority),
        term_io.write_term_3(Ops, Arg2, SecondPriority, !VarSet, !N, !IO),
        maybe_write_paren(')', Priority, OpPriority, !IO)
    ;
        (
            Args = [],
            Functor = term.atom(Op),
            ops.lookup_op(Ops, Op),
            Priority =< ops.max_priority(Ops)
        ->
            io.write_char('(', !IO),
            term_io.write_constant(Functor, !IO),
            io.write_char(')', !IO)
        ;
            term_io.write_constant(Functor,
                maybe_adjacent_to_graphic_token, !IO)
        ),
        (
            Args = [X | Xs],
            io.write_char('(', !IO),
            term_io.write_arg_term(Ops, X, !VarSet, !N, !IO),
            term_io.write_term_args(Ops, Xs, !VarSet, !N, !IO),
            io.write_char(')', !IO)
        ;
            Args = []
        )
    ).

:- pred term_io.write_list_tail(Ops::in, term(T)::in,
    varset(T)::in, varset(T)::out, int::in, int::out, io::di, io::uo) is det
    <= op_table(Ops).

term_io.write_list_tail(Ops, Term, !VarSet, !N, !IO) :-
    (
        Term = term.variable(Id),
        varset.search_var(!.VarSet, Id, Val)
    ->
        term_io.write_list_tail(Ops, Val, !VarSet, !N, !IO)
    ;
        Term = term.functor(term.atom("[|]"), [ListHead, ListTail], _)
    ->
        io.write_string(", ", !IO),
        term_io.write_arg_term(Ops, ListHead, !VarSet, !N, !IO),
        term_io.write_list_tail(Ops, ListTail, !VarSet, !N, !IO)
    ;
        Term = term.functor(term.atom("[]"), [], _)
    ->
        true
    ;
        io.write_string(" | ", !IO),
        term_io.write_term_2(Ops, Term, !VarSet, !N, !IO)
    ).

    % Succeeds iff outputting the given term would start with a digit.
    % (This is a safe, conservative approximation and is used to decide
    % whether or not to quote infix '.'/2.)
    %
:- pred starts_with_digit(term(T)::in) is semidet.

starts_with_digit(functor(integer(_), _, _)).
starts_with_digit(functor(float(_), _, _)).
starts_with_digit(functor(atom(Op), Args, _)) :-
    (
        Args = [Arg, _],
        ops.lookup_infix_op(ops.init_mercury_op_table, Op, _, _, _)
    ;
        Args = [Arg],
        ops.lookup_postfix_op(ops.init_mercury_op_table, Op, _, _)
    ),
    starts_with_digit(Arg).

%-----------------------------------------------------------------------------%

:- pred term_io.write_term_args(Ops::in, list(term(T))::in,
    varset(T)::in, varset(T)::out, int::in, int::out, io::di, io::uo) is det
    <= op_table(Ops).

    % write the remaining arguments
term_io.write_term_args(_, [], !VarSet, !N, !IO).
term_io.write_term_args(Ops, [X | Xs], !VarSet, !N, !IO) :-
    io.write_string(", ", !IO),
    term_io.write_arg_term(Ops, X, !VarSet, !N, !IO),
    term_io.write_term_args(Ops, Xs, !VarSet, !N, !IO).

%-----------------------------------------------------------------------------%

term_io.write_constant(Const, !IO) :-
    term_io.write_constant(Const, not_adjacent_to_graphic_token, !IO).

:- pred term_io.write_constant(const::in, adjacent_to_graphic_token::in,
    io::di, io::uo) is det.

term_io.write_constant(term.integer(I), _, !IO) :-
    io.write_int(I, !IO).
term_io.write_constant(term.float(F), _, !IO) :-
    io.write_float(F, !IO).
term_io.write_constant(term.atom(A), NextToGraphicToken, !IO) :-
    term_io.quote_atom(A, NextToGraphicToken, !IO).
term_io.write_constant(term.string(S), _, !IO) :-
    term_io.quote_string(S, !IO).

term_io.format_constant(Const) =
    term_io.format_constant(Const, not_adjacent_to_graphic_token).

:- func term_io.format_constant(const, adjacent_to_graphic_token) = string.

term_io.format_constant(term.integer(I), _) =
    string.int_to_string(I).
term_io.format_constant(term.float(F), _) =
    string.float_to_string(F).
term_io.format_constant(term.atom(A), NextToGraphicToken) =
    term_io.quoted_atom(A, NextToGraphicToken).
term_io.format_constant(term.string(S), _) =
    term_io.quoted_string(S).

%-----------------------------------------------------------------------------%

term_io.quote_char(C, !IO) :-
    io.write_string(term_io.quoted_char(C), !IO).

term_io.quoted_char(C) =
    string.format("'%s'", [s(term_io.escaped_char(C))]).

term_io.quote_atom(S, !IO) :-
    term_io.quote_atom(S, not_adjacent_to_graphic_token, !IO).

term_io.quoted_atom(S) =
    term_io.quoted_atom(S, not_adjacent_to_graphic_token).

term_io.quote_atom(S, NextToGraphicToken, !IO) :-
    ShouldQuote = should_atom_be_quoted(S, NextToGraphicToken),
    (
        ShouldQuote = no,
        io.write_string(S, !IO)
    ;
        ShouldQuote = yes,
        io.write_char('''', !IO),
        term_io.write_escaped_string(S, !IO),
        io.write_char('''', !IO)
    ).

term_io.quoted_atom(S, NextToGraphicToken) = String :-
    ShouldQuote = should_atom_be_quoted(S, NextToGraphicToken),
    (
        ShouldQuote = no,
        String = S
    ;
        ShouldQuote = yes,
        ES = term_io.escaped_string(S),
        String = string.append_list(["'", ES, "'"])
    ).

:- func should_atom_be_quoted(string, adjacent_to_graphic_token) = bool.

should_atom_be_quoted(S, NextToGraphicToken) = ShouldQuote :-
    (
        % I didn't make these rules up: see ISO Prolog 6.3.1.3 and 6.4.2. -fjh
        (
            % Letter digit token (6.4.2)
            string.first_char(S, FirstChar, Rest),
            char.is_lower(FirstChar),
            string.is_alnum_or_underscore(Rest)
        ;
            % Semicolon token (6.4.2)
            S = ";"
        ;
            % Cut token (6.4.2)
            S = "!"
        ;
            % Graphic token (6.4.2)
            string.to_char_list(S, Chars),
            (
                list.member(Char, Chars)
            =>
                lexer.graphic_token_char(Char)
            ),
            Chars = [_ | _],

            % We need to quote tokens starting with '#', because Mercury uses
            % '#' to start source line number indicators.
            Chars \= ['#' | _],

            % If the token could be the last token in a term, and the term
            % could be followed with ".\n", then we need to quote the token,
            % otherwise the "." would be considered part of the same graphic
            % token. We can only leave it unquoted if we're sure it won't be
            % adjacent to any graphic token.
            NextToGraphicToken = not_adjacent_to_graphic_token
        ;
            % 6.3.1.3: atom = open list, close list ;
            S = "[]"
        ;
            % 6.3.1.3: atom = open curly, close curly ;
            S = "{}"
        )
    ->
        ShouldQuote = no
    ;
        % Anything else must be output as a quoted token (6.4.2).
        ShouldQuote = yes
    ).

% Note: the code here is similar to code in compiler/mercury_to_mercury.m;
% any changes here may require similar changes there.

term_io.quote_string(S, !IO) :-
    io.write_char('"', !IO),
    term_io.write_escaped_string(S, !IO),
    io.write_char('"', !IO).

term_io.quoted_string(S) =
    string.append_list(["""", term_io.escaped_string(S), """"]).

term_io.write_escaped_string(String, !IO) :-
    string.foldl(term_io.write_escaped_char, String, !IO).

term_io.escaped_string(String) =
    string.foldl(term_io.add_escaped_char, String, "").

:- func term_io.add_escaped_char(char, string) = string.

term_io.add_escaped_char(Char, String0) = String :-
    ( mercury_escape_special_char(Char, QuoteChar) ->
        String = String0 ++ from_char_list(['\\', QuoteChar])
    ; is_mercury_source_char(Char) ->
        String = String0 ++ string.char_to_string(Char)
    ;
        String = String0 ++ mercury_escape_char(Char)
    ).

% Note: the code of add_escaped_char and write_escaped_char should be
% kept in sync. The code of both is similar to code in
% compiler/mercury_to_mercury.m; any changes here may require
% similar changes there.

term_io.write_escaped_char(Char, !IO) :-
    ( mercury_escape_special_char(Char, QuoteChar) ->
        io.write_char('\\', !IO),
        io.write_char(QuoteChar, !IO)
    ; is_mercury_source_char(Char) ->
        io.write_char(Char, !IO)
    ;
        io.write_string(mercury_escape_char(Char), !IO)
    ).

term_io.escaped_char(Char) = String :-
    ( mercury_escape_special_char(Char, QuoteChar) ->
        String = string.append("\\",
            string.char_to_string(QuoteChar))
    ; is_mercury_source_char(Char) ->
        String = string.char_to_string(Char)
    ;
        String = mercury_escape_char(Char)
    ).

    % Convert a character to the corresponding octal escape code.
    %
    % We use ISO-Prolog style octal escapes, which are of the form '\nnn\';
    % note that unlike C octal escapes, they are terminated with a backslash.
    %
    % Note: the code here is similar to code in compiler/mercury_to_mercury.m;
    % any changes here may require similar changes there.
    %
:- func mercury_escape_char(char) = string.

mercury_escape_char(Char) = EscapeCode :-
    char.to_int(Char, Int),
    string.int_to_base_string(Int, 8, OctalString0),
    string.pad_left(OctalString0, '0', 3, OctalString),
    EscapeCode = "\\" ++ OctalString ++ "\\".

    % Succeed if Char is a character which is allowed in Mercury string
    % and character literals.
    %
    % Note: the code here is similar to code in compiler/mercury_to_mercury.m;
    % any changes here may require similar changes there.
    %
:- pred is_mercury_source_char(char::in) is semidet.

is_mercury_source_char(Char) :-
    ( char.is_alnum(Char) ->
        true
    ; is_mercury_punctuation_char(Char) ->
        true
    ;
        fail
    ).

    % Currently we only allow the following characters.
    % XXX should we just use is_printable(Char) instead?
    %
    % Note: the code here is similar to code in compiler/mercury_to_mercury.m
    % and also runtime/mercury_trace_base.c; any changes here may require
    % similar changes there.
    %
:- pred is_mercury_punctuation_char(char::in) is semidet.

is_mercury_punctuation_char(' ').
is_mercury_punctuation_char('!').
is_mercury_punctuation_char('@').
is_mercury_punctuation_char('#').
is_mercury_punctuation_char('$').
is_mercury_punctuation_char('%').
is_mercury_punctuation_char('^').
is_mercury_punctuation_char('&').
is_mercury_punctuation_char('*').
is_mercury_punctuation_char('(').
is_mercury_punctuation_char(')').
is_mercury_punctuation_char('-').
is_mercury_punctuation_char('_').
is_mercury_punctuation_char('+').
is_mercury_punctuation_char('=').
is_mercury_punctuation_char('`').
is_mercury_punctuation_char('~').
is_mercury_punctuation_char('{').
is_mercury_punctuation_char('}').
is_mercury_punctuation_char('[').
is_mercury_punctuation_char(']').
is_mercury_punctuation_char(';').
is_mercury_punctuation_char(':').
is_mercury_punctuation_char('''').
is_mercury_punctuation_char('"').
is_mercury_punctuation_char('<').
is_mercury_punctuation_char('>').
is_mercury_punctuation_char('.').
is_mercury_punctuation_char(',').
is_mercury_punctuation_char('/').
is_mercury_punctuation_char('?').
is_mercury_punctuation_char('\\').
is_mercury_punctuation_char('|').

%-----------------------------------------------------------------------------%

    % mercury_escape_special_char(Char, EscapeChar) is true iff Char
    % is character for which there is a special backslash-escape character
    % EscapeChar that can be used after a backslash in string literals or
    % atoms to represent Char.
    %
    % Note: the code here is similar to code in compiler/mercury_to_mercury.m;
    % any changes here may require similar changes there.
    %
:- pred mercury_escape_special_char(char::in, char::out) is semidet.

mercury_escape_special_char('''', '''').
mercury_escape_special_char('"', '"').
mercury_escape_special_char('\\', '\\').
mercury_escape_special_char('\n', 'n').
mercury_escape_special_char('\t', 't').
mercury_escape_special_char('\b', 'b').

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

term_io.write_term_nl(VarSet, Term, !IO) :-
    io.get_op_table(Ops, !IO),
    term_io.write_term_nl_with_op_table(Ops, VarSet, Term, !IO).

term_io.write_term_nl_with_op_table(Ops, VarSet, Term, !IO) :-
    term_io.write_term_with_op_table(Ops, VarSet, Term, !IO),
    io.write_string(".\n", !IO).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
