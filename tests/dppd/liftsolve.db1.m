%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%
%
% The "liftsolve.db1" Benchmark
% Part of the DPPD Library.
% 
% Specialise the lifting meta-interpreter for the ground representation
% (adapted from a "non-executable" one by John Gallagher, similar to the
% InstanceDemo by Hill and Gallagher) with a simple object program which
% can be fully unfolded. Some details about this meta-interpreter can
% also be found in a PEPM'95 paper by Michael Leuschel and Danny De Schreye.
% 
% /* --------------------- */
% /* solve(GrRules, NgGoal) */
% /* --------------------- */
% solve(GrRules, []).
% solve(GrRules, [NgH | NgT]) :-
%         non_ground_member(term(clause, [NgH | NgBody]), GrRules),
%         solve(GrRules, NgBody),
%         solve(GrRules, NgT).
% 
% /* -------------------------------------- */
% /* non_ground_member(NgExpr, GrListOfExpr) */
% /* -------------------------------------- */
% non_ground_member(NgX, [GrH | GrT]) :-
%         make_non_ground(GrH, NgX).
% non_ground_member(NgX, [GrH | GrT]) :-
%         non_ground_member(NgX, GrT).
% 
% /* --------------------------------------------------- */
% /* make_non_ground(GroundRepOfExpr, NonGroundRepOfExpr) */
% /* --------------------------------------------------- */
% make_non_ground(G, NG) :-
%         mkng(G, NG, [], Sub).
% 
% mkng(var(N), X, [], [sub(N, X)]).
% mkng(var(N), X, [sub(N, X) | T], [sub(N, X) | T]).
% mkng(var(N), X, [sub(M, Y) | T], [sub(M, Y) | T1]) :-
%         N \== M,
%         mkng(var(N), X, T, T1).
% mkng(term(F, Args), term(F, IArgs), InSub, OutSub) :-
%         l_mkng(Args, IArgs, InSub, OutSub).
% 
% l_mkng([], [], Sub, Sub).
% l_mkng([H | T], [IH | IT], InSub, OutSub) :-
%         mkng(H, IH, InSub, IntSub),
%         l_mkng(T, IT, IntSub, OutSub).
% 
% member(X, [X | T]).
% member(X, [Y | T]) :-
%         member(X, T).
% 
% append([], L, L).
% append([H | T], M, [H | T2]) :-
%         append(T, M, T2).
% 
%   The partial deduction query
% 
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [X, Y])]).
% 
%   The run-time queries
% 
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [X, Y])]).
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [term(a, []), Y])]).
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [term(a, []), term(b, [])])]).
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [term(a, []), term(c, [])])]).
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [term(c, []), Y])]).
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [X, term(b, [])])]).
%  :- solve([
%           term(clause, [term(father, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(male, [var(x)])]),
%           term(clause, [term(mother, [var(x), var(y)]),
%                 term(parent, [var(x), var(y)]), term(female, [var(x)])]),
%           term(clause, [term(parent, [term(a, []), term(b, [])])]),
%           term(clause, [term(male, [term(a, [])])])],
%         [term(father, [X, term(f, [term(c, [])])])]).
% 
%   Example solution
% 
%    This benchmark can be fully unfolded. With the ECCE partial deduction
%    system one can obtain the following:
% 
%  solve__1(term(a, []), term(b, [])).
% 
% Michael Leuschel / K.U. Leuven / michael@cs.kuleuven.ac.be
