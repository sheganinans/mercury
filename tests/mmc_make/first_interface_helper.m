%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%

:- module first_interface_helper.
:- interface.

:- type tree
    --->    leaf(int)
    ;       fork(tree, tree).

:- func sum(tree) = int.

:- implementation.

:- import_module int.

sum(leaf(Value)) = Value.
sum(fork(Left, Right)) = sum(Left) + sum(Right).
