%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% A fresh explicit short-interface build must remain usable by its consumer.
%---------------------------------------------------------------------------%

:- module first_interface.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module first_interface_helper.

main(!IO) :-
    Tree = fork(leaf(3), fork(leaf(5), leaf(7))),
    io.write_int(sum(Tree), !IO),
    io.nl(!IO).
