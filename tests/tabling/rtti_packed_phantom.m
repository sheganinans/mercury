%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%
% Packed phantom arguments have no existential type-info vector in their
% enclosing constructor. Generic operations must recover each argument's type
% from the enclosing type parameters without accessing an absent heap cell.
% Exercise both type instantiations through copy, ordering, memo lookup and
% existential univ deconstruction across 64 cycles of forced collections.
% Requires --allow-packing-local-sectags; no word-size or tag-layout oracle.
%---------------------------------------------------------------------------%

:- module rtti_packed_phantom.
:- interface.
:- import_module io.
:- pred main(io::di, io::uo) is det.

:- implementation.
:- import_module deconstruct.
:- import_module gc.
:- import_module int.
:- import_module list.
:- import_module require.
:- import_module string.
:- import_module univ.

:- pragma require_feature_set([memo]).

:- type phantom(T)
    --->    ph_zero
    ;       ph_one.

:- type packed(T)
    --->    empty
    ;       pair(first :: phantom(T), second :: phantom(T))
    ;       remote(phantom(T), string).

main(!IO) :-
    A = (pair(ph_zero, ph_one) : packed(list(int))),
    B = (pair(ph_one, ph_zero) : packed(list(int))),
    C = (pair(ph_zero, ph_one) : packed(string)),
    D = (pair(ph_one, ph_zero) : packed(string)),
    ExpectedA = [univ(ph_zero : phantom(list(int))),
        univ(ph_one : phantom(list(int)))],
    ExpectedC = [univ(ph_zero : phantom(string)),
        univ(ph_one : phantom(string))],
    cycles(64, A, B, C, D, ExpectedA, ExpectedC, !IO),
    io.write_string("packed phantom RTTI: ok (64 cycles)\n", !IO).

:- pred cycles(int::in, packed(list(int))::in, packed(list(int))::in,
    packed(string)::in, packed(string)::in, list(univ)::in, list(univ)::in,
    io::di, io::uo) is det.

cycles(N, A, B, C, D, ExpectedA, ExpectedC, !IO) :-
    ( if N = 0 then
        true
    else
        gc.garbage_collect(!IO),
        exercise(A, B, ExpectedA),
        exercise(C, D, ExpectedC),
        gc.garbage_collect(!IO),
        remembered(A, SavedA),
        remembered(C, SavedC),
        inspect(SavedA, ExpectedA),
        inspect(SavedC, ExpectedC),
        cycles(N - 1, A, B, C, D, ExpectedA, ExpectedC, !IO)
    ).

:- pred exercise(T::in, T::in, list(univ)::in) is det.
:- pragma no_inline(exercise/3).

exercise(Value, Other, ExpectedArgs) :-
    copy(Value, Copied),
    remembered(Copied, Saved),
    inspect(Copied, ExpectedArgs),
    inspect(Saved, ExpectedArgs),
    compare(Ord, Value, Other),
    ( if Ord = (<), same(Value, Saved) then
        true
    else
        error("packed phantom copy/compare/table mismatch")
    ).

:- pred inspect(T::in, list(univ)::in) is det.
:- pragma no_inline(inspect/2).

inspect(Value, ExpectedArgs) :-
    deconstruct(Value, do_not_allow, Name, Arity, Args),
    ( if
        Name = "pair",
        Arity = 2,
        Args = ExpectedArgs,
        arg(Value, do_not_allow, 0, First),
        named_arg(Value, do_not_allow, "second", Second),
        ExpectedArgs = [univ(First), univ(Second)]
    then
        true
    else
        error("packed phantom deconstruction/typeinfo mismatch")
    ).

:- pred same(T::in, T::in) is semidet.
:- pragma no_inline(same/2).
same(X, X).

:- pred remembered(T::in, T::out) is det.
:- pragma memo(remembered/2).
remembered(X, X).
