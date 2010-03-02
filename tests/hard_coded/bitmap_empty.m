%-----------------------------------------------------------------------------%
% Test operations on empty (zero-length) bitmaps.

:- module bitmap_empty.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is cc_multi.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module bitmap.
:- import_module bool.
:- import_module list.

%-----------------------------------------------------------------------------%

main(!IO) :-
    io.write_string("-- new\n", !IO),
    A0 = bitmap.new(0, no) : bitmap,
    io.write(A0, !IO),
    io.nl(!IO),

    io.write_string("-- copy\n", !IO),
    some [B] (
        copy(A0, B),
        io.write(B, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- resize\n", !IO),
    some [B0, B1, B2, B3] (
        B0 = bitmap.new(0, no),
        B1 = resize(B0, 0, no),     % no change
        io.write(B1, !IO),
        io.nl(!IO),
        B2 = resize(B1, 4, yes),    % enlarge
        io.write(B2, !IO),
        io.nl(!IO),
        B3 = resize(B2, 0, yes),    % shrink
        io.write(B3, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- shrink_without_copying\n", !IO),
    some [B0, B1] (
        B0 = bitmap.new(4, no),
        B1 = shrink_without_copying(B0, 0),
        io.write(B1, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- in_range\n", !IO),
    ( in_range(A0, -1) ->
        io.write_string("error\n", !IO)
    ;
        io.write_string("ok\n", !IO)
    ),
    ( in_range(A0, 0) ->
        io.write_string("error\n", !IO)
    ;
        io.write_string("ok\n", !IO)
    ),
    ( in_range(A0, 1) ->
        io.write_string("error\n", !IO)
    ;
        io.write_string("ok\n", !IO)
    ),

    io.write_string("-- byte_in_range\n", !IO),
    ( byte_in_range(A0, -1) ->
        io.write_string("error\n", !IO)
    ;
        io.write_string("ok\n", !IO)
    ),
    ( byte_in_range(A0, 0) ->
        io.write_string("error\n", !IO)
    ;
        io.write_string("ok\n", !IO)
    ),
    ( byte_in_range(A0, 1) ->
        io.write_string("error\n", !IO)
    ;
        io.write_string("ok\n", !IO)
    ),

    io.write_string("-- num_bits\n", !IO),
    NumBits = num_bits(A0),
    io.write_int(NumBits, !IO),
    io.nl(!IO),

    io.write_string("-- det_num_bytes\n", !IO),
    NumBytes = det_num_bytes(A0),
    io.write_int(NumBytes, !IO),
    io.nl(!IO),

    io.write_string("-- ^bit\n", !IO),
    (try []
        Bit = A0 ^ bit(0)
    then
        io.write(Bit, !IO),
        io.nl(!IO)
    catch_any BitExcp ->
        io.write_string("expected: ", !IO),
        io.write(BitExcp, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- ^bits\n", !IO),
    Bits = A0 ^ bits(0, 0),
    io.write(Bits, !IO),
    io.nl(!IO),

    io.write_string("-- ^bits:=\n", !IO),
    some [B0, B1] (
        B0 = bitmap.new(0, no),
        B1 = B0 ^ bits(0, 0) := 0,
        io.write(B1, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- ^byte\n", !IO),
    (try []
        Byte = A0 ^ byte(0)
    then
        io.write(Byte, !IO),
        io.nl(!IO)
    catch_any ByteExcp ->
        io.write_string("expected: ", !IO),
        io.write(ByteExcp, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- ^byte:=\n", !IO),
    some [B0, B1] (
        (try [] (
            B0 = bitmap.new(0, no),
            B1 = B0 ^ byte(0) := 0
        )
        then
            io.write(B1, !IO),
            io.nl(!IO)
        catch_any SetByteExcp ->
            io.write_string("expected: ", !IO),
            io.write(SetByteExcp, !IO),
            io.nl(!IO)
        )
    ),

    io.write_string("-- slice\n", !IO),
    some [S] (
        S = bitmap.slice(A0, 0, 0),
        io.write(S, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- byte_slice\n", !IO),
    some [S] (
        S = bitmap.byte_slice(A0, 0, 0),
        io.write(S, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- flip\n", !IO),
    some [B0, B1] (
        (try [] (
            B0 = bitmap.new(0, no),
            B1 = flip(B0, 0)
        )
        then
            io.write(B1, !IO)
        catch_any E18 ->
            io.write_string("expected: ", !IO),
            io.write(E18, !IO),
            io.nl(!IO)
        )
    ),

    A1 = bitmap.new(0, no),
    A2 = bitmap.new(0, no),

    io.write_string("-- complement\n", !IO),
    Bcompl = complement(A1),
    io.write(Bcompl, !IO),
    io.nl(!IO),

    io.write_string("-- union\n", !IO),
    Bunion = union(A1, A2),
    io.write(Bunion, !IO),
    io.nl(!IO),

    io.write_string("-- intersect\n", !IO),
    Bintersect = intersect(A1, A2),
    io.write(Bintersect, !IO),
    io.nl(!IO),

    io.write_string("-- difference\n", !IO),
    Bdiff = difference(A1, A2),
    io.write(Bdiff, !IO),
    io.nl(!IO),

    io.write_string("-- xor\n", !IO),
    Bxor = xor(A1, A2),
    io.write(Bxor, !IO),
    io.nl(!IO),

    io.write_string("-- append_list\n", !IO),
    some [B0, B1, B2, B3] (
        B0 = bitmap.new(1, yes),
        B1 = bitmap.new(0, yes),
        B2 = bitmap.new(1, yes),
        B3 = append_list([B0, B1, B2]),
        io.write(B3, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- copy_bits\n", !IO),
    some [B0, B1, B2] (
        B0 = bitmap.new(1, yes),
        B1 = bitmap.new(0, yes),
        B2 = copy_bits(B0, 0, B1, 0, 0),
        io.write(B2, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- copy_bits_in_bitmap\n", !IO),
    some [B0, B1] (
        B0 = bitmap.new(0, no),
        B1 = copy_bits_in_bitmap(B0, 0, 0, 0),
        io.write(B1, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- copy_bytes\n", !IO),
    some [B0, B1, B2] (
        B0 = bitmap.new(8, yes),
        B1 = bitmap.new(0, no),
        B2 = copy_bytes(B0, 0, B1, 0, 0),
        io.write(B2, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- copy_bytes_in_bitmap\n", !IO),
    some [B0, B1] (
        B0 = bitmap.new(0, no),
        B1 = copy_bytes_in_bitmap(B0, 0, 0, 0),
        io.write(B1, !IO),
        io.nl(!IO)
    ),

    io.write_string("-- from_string\n", !IO),
    String = to_string(A0),
    ( Bstring = bitmap.from_string(String) ->
        io.write(Bstring, !IO),
        io.nl(!IO)
    ;
        io.write_string("error\n", !IO)
    ),

    io.write_string("-- to_byte_string\n", !IO),
    ByteString = bitmap.to_byte_string(A0),
    io.write_string("<", !IO),
    io.write_string(ByteString, !IO),
    io.write_string(">\n", !IO),

    io.write_string("-- hash\n", !IO),
    Hash = bitmap.hash(A0),
    io.write_int(Hash, !IO),
    io.nl(!IO),

    io.write_string("-- bitmap_equal\n", !IO),
    some [B0, B1] (
        B0 = bitmap.new(0, no),
        B1 = bitmap.new(0, no),
        ( B0 = B1 ->
            io.write_string("equal\n", !IO)
        ;
            io.write_string("not equal\n", !IO)
        )
    ),

    io.write_string("-- bitmap_compare\n", !IO),
    some [B0, B1] (
        B0 = bitmap.new(0, no),
        B1 = bitmap.new(0, no),
        compare(Compare, B0, B1),
        io.write(Compare, !IO),
        io.nl(!IO)
    ).

%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=8 sts=4 sw=4 et
