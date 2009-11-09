%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2009 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: hlds_out_module.m.
% Main authors: conway, fjh.
%
%-----------------------------------------------------------------------------%

:- module hlds.hlds_out.hlds_out_module.
:- interface.

:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_out.hlds_out_util.
:- import_module hlds.hlds_pred.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module io.
:- import_module list.

%-----------------------------------------------------------------------------%

    % Print out an entire HLDS structure.
    %
:- pred write_hlds(int::in, module_info::in, io::di, io::uo) is det.

:- pred write_promise(hlds_out_info::in, promise_type::in, int::in,
    module_info::in, pred_id::in, prog_varset::in, bool::in,
    list(prog_var)::in, pred_or_func::in, clause::in, maybe_vartypes::in,
    io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds.hlds_data.
:- import_module hlds.hlds_out.hlds_out_goal.
:- import_module hlds.hlds_out.hlds_out_pred.
:- import_module hlds.pred_table.
:- import_module libs.compiler_util.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.prog_out.

:- import_module assoc_list.
:- import_module int.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module set.
:- import_module string.
:- import_module term.
:- import_module term_io.

%-----------------------------------------------------------------------------%
%
% Write out (selected parts of) the entire HLDS.
%

write_hlds(Indent, ModuleInfo, !IO) :-
    module_info_get_imported_module_specifiers(ModuleInfo, Imports),
    module_info_preds(ModuleInfo, PredTable),
    module_info_get_type_table(ModuleInfo, TypeTable),
    module_info_get_inst_table(ModuleInfo, InstTable),
    module_info_get_mode_table(ModuleInfo, ModeTable),
    module_info_get_class_table(ModuleInfo, ClassTable),
    module_info_get_instance_table(ModuleInfo, InstanceTable),
    module_info_get_table_struct_map(ModuleInfo, TableStructMap),
    module_info_get_globals(ModuleInfo, Globals),
    globals.lookup_accumulating_option(Globals, dump_hlds_pred_id,
        DumpPredIdStrs),
    globals.lookup_accumulating_option(Globals, dump_hlds_pred_name,
        DumpPredNames),
    write_header(Indent, ModuleInfo, !IO),
    Info = init_hlds_out_info(Globals),
    (
        % If the user specifically requested one or more predicates and/or
        % functions to be dumped, they won't be interested in the types,
        % insts etc.
        ( DumpPredIdStrs = [_ | _]
        ; DumpPredNames = [_ | _]
        )
    ->
        true
    ;
        DumpOptions = Info ^ hoi_dump_hlds_options,
        ( string.contains_char(DumpOptions, 'I') ->
            write_imports(Indent, Imports, !IO)
        ;
            true
        ),
        ( string.contains_char(DumpOptions, 'T') ->
            write_types(Info, Indent, TypeTable, !IO),
            io.write_string("\n", !IO),
            write_classes(Info, Indent, ClassTable, !IO),
            io.write_string("\n", !IO),
            write_instances(Info, Indent, InstanceTable, !IO),
            io.write_string("\n", !IO)
        ;
            true
        ),
        ( string.contains_char(DumpOptions, 'M') ->
            write_insts(Indent, InstTable, !IO),
            io.write_string("\n", !IO),
            write_modes(Indent, ModeTable, !IO),
            io.write_string("\n", !IO)
        ;
            true
        ),
        ( string.contains_char(DumpOptions, 'Z') ->
            write_table_structs(ModuleInfo, TableStructMap, !IO),
            io.write_string("\n", !IO)
        ;
            true
        )
    ),
    write_preds(Info, Indent, ModuleInfo, PredTable, !IO),
    write_footer(Indent, ModuleInfo, !IO).

%-----------------------------------------------------------------------------%

:- pred write_header(int::in, module_info::in, io::di, io::uo) is det.

write_header(Indent, Module, !IO) :-
    write_indent(Indent, !IO),
    io.write_string("% vim: ts=2 sw=2\n\n", !IO),
    module_info_get_name(Module, Name),
    write_indent(Indent, !IO),
    io.write_string(":- module ", !IO),
    prog_out.write_sym_name(Name, !IO),
    io.write_string(".\n\n", !IO).

:- pred write_footer(int::in, module_info::in, io::di, io::uo) is det.

write_footer(Indent, Module, !IO) :-
    module_info_get_name(Module, Name),
    write_indent(Indent, !IO),
    io.write_string(":- end_module ", !IO),
    prog_out.write_sym_name(Name, !IO),
    io.write_string(".\n", !IO).

%-----------------------------------------------------------------------------%
%
% Write out the imports.
%

:- pred write_imports(int::in, set(module_specifier)::in, io::di, io::uo)
    is det.

write_imports(Indent, ImportSet, !IO) :-
    write_indent(Indent, !IO),
    io.write_string(":- import_module ", !IO),
    io.write_list(set.to_sorted_list(ImportSet), ", ", write_sym_name, !IO),
    io.write_string(".\n\n", !IO).

%-----------------------------------------------------------------------------%
%
% Write out the type table.
%

:- pred write_types(hlds_out_info::in, int::in, type_table::in,
    io::di, io::uo) is det.

write_types(Info, Indent, TypeTable, !IO) :-
    write_indent(Indent, !IO),
    io.write_string("%-------- Types --------\n", !IO),
    get_all_type_ctor_defns(TypeTable, TypeAssocList),
    write_types_2(Info, Indent, TypeAssocList, !IO).

:- pred write_types_2(hlds_out_info::in, int::in,
    assoc_list(type_ctor, hlds_type_defn)::in, io::di, io::uo) is det.

write_types_2(_, _, [], !IO).
write_types_2(Info, Indent, [TypeCtor - TypeDefn | Types], !IO) :-
    hlds_data.get_type_defn_tvarset(TypeDefn, TVarSet),
    hlds_data.get_type_defn_tparams(TypeDefn, TypeParams),
    hlds_data.get_type_defn_body(TypeDefn, TypeBody),
    hlds_data.get_type_defn_status(TypeDefn, Status),
    hlds_data.get_type_defn_context(TypeDefn, Context),

    % Write the context.
    io.write_char('\n', !IO),
    DumpOptions = Info ^ hoi_dump_hlds_options,
    ( string.contains_char(DumpOptions, 'c') ->
        term.context_file(Context, FileName),
        term.context_line(Context, LineNumber),
        ( FileName \= "" ->
            write_indent(Indent, !IO),
            io.write_string("% context: file `", !IO),
            io.write_string(FileName, !IO),
            io.write_string("', line ", !IO),
            io.write_int(LineNumber, !IO),
            io.write_string(", status ", !IO),
            io.write_string(import_status_to_string(Status), !IO),
            io.write_char('\n', !IO)
        ;
            true
        )
    ;
        true
    ),

    write_indent(Indent, !IO),
    (
        ( TypeBody = hlds_solver_type(_, _)
        ; TypeBody = hlds_abstract_type(solver_type)
        )
    ->
        io.write_string(":- solver type ", !IO)
    ;
        io.write_string(":- type ", !IO)
    ),
    write_type_name(TypeCtor, !IO),
    write_type_params(TVarSet, TypeParams, !IO),
    write_type_body(Info, TypeCtor, TypeBody, Indent + 1, TVarSet, !IO),
    write_types_2(Info, Indent, Types, !IO).

:- pred write_type_params(tvarset::in, list(type_param)::in,
    io::di, io::uo) is det.

write_type_params(_TVarSet, [], !IO).
write_type_params(TVarSet, [P], !IO) :-
    io.write_string("(", !IO),
    mercury_output_var(TVarSet, no, P, !IO),
    io.write_string(")", !IO).
write_type_params(TVarSet, [P | Ps], !IO) :-
    Ps = [_ | _],
    io.write_string("(", !IO),
    mercury_output_var(TVarSet, no, P, !IO),
    write_type_params_2(TVarSet, Ps, !IO).

:- pred write_type_params_2(tvarset::in, list(type_param)::in,
    io::di, io::uo) is det.

write_type_params_2(_TVarSet, [], !IO) :-
    io.write_string(")", !IO).
write_type_params_2(TVarSet, [P | Ps], !IO) :-
    io.write_string(", ", !IO),
    mercury_output_var(TVarSet, no, P, !IO),
    write_type_params_2(TVarSet, Ps, !IO).

:- pred write_type_body(hlds_out_info::in, type_ctor::in, hlds_type_body::in,
    int::in, tvarset::in, io::di, io::uo) is det.

write_type_body(Info, TypeCtor, TypeBody, Indent, TVarSet, !IO) :-
    (
        TypeBody = hlds_du_type(Ctors, ConsTagMap, CheaperTagTest, DuTypeKind,
            MaybeUserEqComp, ReservedTag, ReservedAddr, Foreign),
        io.write_string(" --->\n", !IO),
        (
            CheaperTagTest = no_cheaper_tag_test
        ;
            CheaperTagTest = cheaper_tag_test(ExpConsId, ExpConsTag,
                CheapConsId, CheapConsTag),
            io.write_string("/* cheaper tag test: ", !IO),
            write_cons_id_and_arity(ExpConsId, !IO),
            io.write_string(" tag ", !IO),
            io.print(ExpConsTag, !IO),
            io.write_string(" -> ", !IO),
            write_cons_id_and_arity(CheapConsId, !IO),
            io.write_string(" tag ", !IO),
            io.print(CheapConsTag, !IO),
            io.write_string(" */\n", !IO)
        ),
        (
            DuTypeKind = du_type_kind_mercury_enum,
            write_indent(Indent, !IO),
            io.write_string("/* KIND enumeration */\n", !IO)
        ;
            DuTypeKind = du_type_kind_foreign_enum(Lang),
            write_indent(Indent, !IO),
            io.write_string("/* KIND foreign enumeration for ", !IO),
            io.write_string(foreign_language_string(Lang), !IO),
            io.write_string(" */\n", !IO)
        ;
            DuTypeKind = du_type_kind_direct_dummy,
            write_indent(Indent, !IO),
            io.write_string("/* KIND dummy */\n", !IO)
        ;
            DuTypeKind = du_type_kind_notag(FunctorName, ArgType,
                MaybeArgName),
            write_indent(Indent, !IO),
            io.write_string("/* KIND notag: ", !IO),
            write_sym_name(FunctorName, !IO),
            io.write_string(", ", !IO),
            mercury_output_type(TVarSet, no, ArgType, !IO),
            io.write_string(", ", !IO),
            (
                MaybeArgName = yes(ArgName),
                io.write_string(ArgName, !IO)
            ;
                MaybeArgName = no,
                io.write_string("no arg name", !IO)
            ),
            io.write_string(" */\n", !IO)
        ;
            DuTypeKind = du_type_kind_general,
            io.write_string("/* KIND general */\n", !IO)
        ),
        (
            ReservedTag = uses_reserved_tag,
            write_indent(Indent, !IO),
            io.write_string("/* reserved_tag */\n", !IO)
        ;
            ReservedTag = does_not_use_reserved_tag
        ),
        (
            ReservedAddr = uses_reserved_address,
            write_indent(Indent, !IO),
            io.write_string("/* reserved_address */\n", !IO)
        ;
            ReservedAddr = does_not_use_reserved_address
        ),
        write_constructors(TypeCtor, Indent, TVarSet, Ctors, ConsTagMap, !IO),
        MercInfo = Info ^ hoi_mercury_to_mercury,
        mercury_output_where_attributes(MercInfo, TVarSet, no, MaybeUserEqComp,
            !IO),
        (
            Foreign = yes(_),
            write_indent(Indent, !IO),
            io.write_string("/* has foreign_type */\n", !IO)
        ;
            Foreign = no
        ),
        io.write_string(".\n", !IO)
    ;
        TypeBody = hlds_eqv_type(Type),
        io.write_string(" == ", !IO),
        mercury_output_type(TVarSet, no, Type, !IO),
        io.write_string(".\n", !IO)
    ;
        TypeBody = hlds_abstract_type(_IsSolverType),
        io.write_string(".\n", !IO)
    ;
        TypeBody = hlds_foreign_type(_),
        % XXX
        io.write_string(" == $foreign_type.\n", !IO)
    ;
        TypeBody = hlds_solver_type(SolverTypeDetails, MaybeUserEqComp),
        MercInfo = Info ^ hoi_mercury_to_mercury,
        mercury_output_where_attributes(MercInfo, TVarSet,
            yes(SolverTypeDetails), MaybeUserEqComp, !IO),
        io.write_string(".\n", !IO)
    ).

:- pred write_constructors(type_ctor::in, int::in, tvarset::in,
    list(constructor)::in, cons_tag_values::in, io::di, io::uo) is det.

write_constructors(_TypeCtor, _Indent, _TVarSet, [], _, !IO) :-
    unexpected(this_file, "write_constructors: empty constructor list?").
write_constructors(TypeCtor, Indent, TVarSet, [Ctor], TagValues, !IO) :-
    write_indent(Indent, !IO),
    io.write_char('\t', !IO),
    write_ctor(TypeCtor, Ctor, TVarSet, TagValues, !IO).
write_constructors(TypeCtor, Indent, TVarSet, [Ctor | Ctors], TagValues,
        !IO) :-
    Ctors = [_ | _],
    write_indent(Indent, !IO),
    io.write_char('\t', !IO),
    write_ctor(TypeCtor, Ctor, TVarSet, TagValues, !IO),
    io.write_string("\n", !IO),
    write_constructors_2(TypeCtor, Indent, TVarSet, Ctors, TagValues, !IO).

:- pred write_constructors_2(type_ctor::in, int::in, tvarset::in,
    list(constructor)::in, cons_tag_values::in, io::di, io::uo) is det.

write_constructors_2(_TypeCtor, _Indent, _TVarSet, [], _, !IO).
write_constructors_2(TypeCtor, Indent, TVarSet, [Ctor | Ctors], TagValues,
        !IO) :-
    write_indent(Indent, !IO),
    io.write_string(";\t", !IO),
    write_ctor(TypeCtor, Ctor, TVarSet, TagValues, !IO),
    (
        Ctors = []
    ;
        Ctors = [_ | _],
        io.write_string("\n", !IO),
        write_constructors_2(TypeCtor, Indent, TVarSet, Ctors, TagValues, !IO)
    ).

:- pred write_ctor(type_ctor::in, constructor::in, tvarset::in,
    cons_tag_values::in, io::di, io::uo) is det.

write_ctor(TypeCtor, Ctor, TVarSet, TagValues, !IO) :-
    mercury_output_ctor(Ctor, TVarSet, !IO),
    Ctor = ctor(_, _, Name, Args, _),
    ConsId = cons(Name, list.length(Args), TypeCtor),
    ( map.search(TagValues, ConsId, TagValue) ->
        io.write_string("\t% tag: ", !IO),
        io.print(TagValue, !IO)
    ;
        true
    ).

%-----------------------------------------------------------------------------%
%
% Write out the typeclass table.
%

:- pred write_classes(hlds_out_info::in, int::in, class_table::in,
    io::di, io::uo) is det.

write_classes(Info, Indent, ClassTable, !IO) :-
    write_indent(Indent, !IO),
    io.write_string("%-------- Classes --------\n", !IO),
    map.to_assoc_list(ClassTable, ClassTableList),
    io.write_list(ClassTableList, "\n", write_class_defn(Info, Indent), !IO),
    io.nl(!IO).

:- pred write_class_defn(hlds_out_info::in, int::in,
    pair(class_id, hlds_class_defn)::in, io::di, io::uo) is det.

write_class_defn(Info, Indent, ClassId - ClassDefn, !IO) :-
    write_indent(Indent, !IO),
    io.write_string("% ", !IO),

    write_class_id(ClassId, !IO),
    io.write_string(":\n", !IO),

    ClassDefn = hlds_class_defn(_, Constraints, FunDeps, _, Vars, _, _,
        Interface, VarSet, Context),

    term.context_file(Context, FileName),
    term.context_line(Context, LineNumber),
    ( FileName \= "" ->
        write_indent(Indent, !IO),
        io.write_string("% context: file `", !IO),
        io.write_string(FileName, !IO),
        io.write_string("', line ", !IO),
        io.write_int(LineNumber, !IO),
        io.write_string("\n", !IO)
    ;
        true
    ),

    DumpOptions = Info ^ hoi_dump_hlds_options,
    ( string.contains_char(DumpOptions, 'v') ->
        AppendVarNums = yes
    ;
        AppendVarNums = no
    ),

    write_indent(Indent, !IO),
    io.write_string("% Vars: ", !IO),
    mercury_output_vars(VarSet, AppendVarNums, Vars, !IO),
    io.nl(!IO),

    write_indent(Indent, !IO),
    io.write_string("% Functional dependencies: ", !IO),
    io.write_list(FunDeps, ", ", hlds_output_fundep, !IO),
    io.nl(!IO),

    write_indent(Indent, !IO),
    io.write_string("% Constraints: ", !IO),
    io.write_list(Constraints, ", ",
        mercury_output_constraint(VarSet, AppendVarNums), !IO),
    io.nl(!IO),

    write_indent(Indent, !IO),
    io.write_string("% Class Methods: ", !IO),
    io.write_list(Interface, ", ", write_class_proc, !IO),
    io.nl(!IO).

:- pred hlds_output_fundep(hlds_class_fundep::in, io::di, io::uo) is det.

hlds_output_fundep(fundep(Domain, Range), !IO) :-
    io.write_char('(', !IO),
    DomainList = set.to_sorted_list(Domain),
    io.write_list(DomainList, ", ", io.write_int, !IO),
    io.write_string(" -> ", !IO),
    RangeList = set.to_sorted_list(Range),
    io.write_list(RangeList, ", ", io.write_int, !IO),
    io.write_char(')', !IO).

    % Just output the class methods as pred_ids and proc_ids because it is
    % probably not that useful to have the names. If that information is
    % needed, it shouldn't be a very difficult fix.
    %
:- pred write_class_proc(hlds_class_proc::in, io::di, io::uo) is det.

write_class_proc(hlds_class_proc(PredId, ProcId), !IO) :-
    io.write_string("hlds_class_proc(pred_id:", !IO),
    pred_id_to_int(PredId, PredInt),
    io.write_int(PredInt, !IO),
    io.write_string(", proc_id:", !IO),
    proc_id_to_int(ProcId, ProcInt),
    io.write_int(ProcInt, !IO),
    io.write_char(')', !IO).

%-----------------------------------------------------------------------------%
%
% Write out the instance table.
%

:- pred write_instances(hlds_out_info::in, int::in, instance_table::in,
    io::di, io::uo) is det.

write_instances(Info, Indent, InstanceTable, !IO) :-
    write_indent(Indent, !IO),
    io.write_string("%-------- Instances --------\n", !IO),
    map.to_assoc_list(InstanceTable, InstanceTableList),
    io.write_list(InstanceTableList, "\n\n",
        write_instance_defns(Info, Indent), !IO),
    io.nl(!IO).

:- pred write_instance_defns(hlds_out_info::in, int::in,
    pair(class_id, list(hlds_instance_defn))::in, io::di, io::uo) is det.

write_instance_defns(Info, Indent, ClassId - InstanceDefns, !IO) :-
    write_indent(Indent, !IO),
    io.write_string("% ", !IO),
    write_class_id(ClassId, !IO),
    io.write_string(":\n", !IO),
    io.write_list(InstanceDefns, "\n", write_instance_defn(Info, Indent),
        !IO).

:- pred write_instance_defn(hlds_out_info::in, int::in, hlds_instance_defn::in,
    io::di, io::uo) is det.

write_instance_defn(Info, Indent, InstanceDefn, !IO) :-
    InstanceDefn = hlds_instance_defn(_InstanceModule, _Status,
        Context, Constraints, Types, Body, MaybePredProcIds, VarSet, Proofs),

    term.context_file(Context, FileName),
    term.context_line(Context, LineNumber),
    ( FileName \= "" ->
        write_indent(Indent, !IO),
        io.write_string("% context: file `", !IO),
        io.write_string(FileName, !IO),
        io.write_string("', line ", !IO),
        io.write_int(LineNumber, !IO),
        io.write_string("\n", !IO)
    ;
        true
    ),

    DumpOptions = Info ^ hoi_dump_hlds_options,
    ( string.contains_char(DumpOptions, 'v') ->
        AppendVarNums = yes
    ;
        AppendVarNums = no
    ),

    % Curry the varset for term_io.write_variable/4.
    PrintTerm = (pred(TypeName::in, IO0::di, IO::uo) is det :-
        mercury_output_type(VarSet, AppendVarNums, TypeName, IO0, IO)
    ),
    write_indent(Indent, !IO),
    io.write_string("% Types: ", !IO),
    io.write_list(Types, ", ", PrintTerm, !IO),
    io.nl(!IO),

    write_indent(Indent, !IO),
    io.write_string("% Constraints: ", !IO),
    io.write_list(Constraints, ", ",
        mercury_output_constraint(VarSet, AppendVarNums), !IO),
    io.nl(!IO),

    write_indent(Indent, !IO),
    (
        Body = instance_body_abstract,
        io.write_string("% abstract", !IO)
    ;
        Body = instance_body_concrete(Methods),
        io.write_string("% Instance Methods: ", !IO),
        mercury_output_instance_methods(Methods, !IO)
    ),
    io.nl(!IO),

    (
        MaybePredProcIds = yes(PredProcIds),
        write_indent(Indent, !IO),
        io.write_string("% procedures: ", !IO),
        io.write(PredProcIds, !IO),
        io.nl(!IO)
    ;
        MaybePredProcIds = no
    ),
    write_constraint_proofs(Indent, VarSet, Proofs, AppendVarNums, !IO),
    io.nl(!IO).

%-----------------------------------------------------------------------------%
%
% Write out the inst table.
%

:- pred write_insts(int::in, inst_table::in, io::di, io::uo) is det.

write_insts(Indent, _InstTable, !IO) :-
    % XXX fix this up.
    write_indent(Indent, !IO),
    io.write_string("%-------- Insts --------\n", !IO),
    write_indent(Indent, !IO),
    io.write_string("%%% Not yet implemented, sorry.\n", !IO).
    % io.write_string("% ", !IO).
    % io.print(InstTable, !IO),
    % io.nl(!IO).

%-----------------------------------------------------------------------------%
%
% Write out the mode table.
%

:- pred write_modes(int::in, mode_table::in, io::di, io::uo) is det.

write_modes(Indent, _ModeTable, !IO) :-
    % XXX fix this up.
    write_indent(Indent, !IO),
    io.write_string("%-------- Modes --------\n", !IO),
    write_indent(Indent, !IO),
    io.write_string("%%% Not yet implemented, sorry.\n", !IO).
    % io.write_string("% ", !IO),
    % io.print(ModeTable, !IO),
    % io.nl(!IO).

%-----------------------------------------------------------------------------%
%
% Write out tabling structs defined in the module.
%

:- pred write_table_structs(module_info::in, table_struct_map::in,
    io::di, io::uo) is det.

write_table_structs(ModuleInfo, TableStructMap, !IO) :-
    map.to_assoc_list(TableStructMap, TableStructs),
    io.write_string("%-------- Table structs --------\n", !IO),
    list.foldl(write_table_struct_info(ModuleInfo), TableStructs, !IO),
    io.nl(!IO).

:- pred write_table_struct_info(module_info::in,
    pair(pred_proc_id, table_struct_info)::in, io::di, io::uo) is det.

write_table_struct_info(ModuleInfo, PredProcId - TableStructInfo, !IO) :-
    io.nl(!IO),
    io.write_string("% table struct info for ", !IO),
    write_pred_proc_id(ModuleInfo, PredProcId, !IO),
    io.nl(!IO),
    TableStructInfo = table_struct_info(ProcTableStructInfo, Attributes),
    ProcTableStructInfo = proc_table_struct_info(_ProcLabel, TVarSet, _Context,
        NumInputs, NumOutputs, InputSteps, MaybeOutputSteps, ArgInfos,
        _EvalMethod),
    io.format("%% #inputs: %d, #outputs: %d\n", [i(NumInputs), i(NumOutputs)],
        !IO),
    io.write_string("% input steps:", !IO),
    list.foldl(write_space_and_table_trie_step(TVarSet), InputSteps, !IO),
    io.nl(!IO),
    (
        MaybeOutputSteps = yes(OutputSteps),
        io.write_string("% output steps:", !IO),
        list.foldl(write_space_and_table_trie_step(TVarSet), OutputSteps, !IO),
        io.nl(!IO)
    ;
        MaybeOutputSteps = no,
        io.write_string("% no output steps", !IO)
    ),
    write_table_arg_infos(TVarSet, ArgInfos, !IO),

    Attributes = table_attributes(Strictness, SizeLimit, Stats, AllowReset),
    (
        Strictness = all_strict,
        io.write_string("% all strict\n", !IO)
    ;
        Strictness = all_fast_loose,
        io.write_string("% all fast_loose\n", !IO)
    ;
        Strictness = specified(ArgMethods, HiddenArgMethod),
        io.write_string("% specified [", !IO),
        write_arg_tabling_methods("", ArgMethods, !IO),
        io.write_string("]", !IO),
        (
            HiddenArgMethod = hidden_arg_value,
            io.write_string(", hidden args by value\n", !IO)
        ;
            HiddenArgMethod = hidden_arg_addr,
            io.write_string(", hidden args by addr\n", !IO)
        )
    ),
    (
        SizeLimit = no,
        io.write_string("% no size limit\n", !IO)
    ;
        SizeLimit = yes(Limit),
        io.format("%% size limit %d\n", [i(Limit)], !IO)
    ),
    (
        Stats = table_gather_statistics,
        io.write_string("% gather statistics\n", !IO)
    ;
        Stats = table_dont_gather_statistics,
        io.write_string("% do not gather statistics\n", !IO)
    ),
    (
        AllowReset = table_allow_reset,
        io.write_string("% allow reset\n", !IO)
    ;
        AllowReset = table_dont_allow_reset,
        io.write_string("% do not allow reset\n", !IO)
    ).

:- pred write_arg_tabling_methods(string::in,
    list(maybe(arg_tabling_method))::in, io::di, io::uo) is det.

write_arg_tabling_methods(_Prefix, [], !IO).
write_arg_tabling_methods(Prefix, [MaybeMethod | MaybeMethods], !IO) :-
    io.write_string(Prefix, !IO),
    (
        MaybeMethod = no,
        io.write_string("output", !IO)
    ;
        MaybeMethod = yes(arg_value),
        io.write_string("value", !IO)
    ;
        MaybeMethod = yes(arg_addr),
        io.write_string("addr", !IO)
    ;
        MaybeMethod = yes(arg_promise_implied),
        io.write_string("promise_implied", !IO)
    ),
    write_arg_tabling_methods(", ", MaybeMethods, !IO).

%-----------------------------------------------------------------------------%
%
% Write out the predicate table.
%

:- pred write_preds(hlds_out_info::in, int::in, module_info::in,
    pred_table::in, io::di, io::uo) is det.

write_preds(Info, Indent, ModuleInfo, PredTable, !IO) :-
    io.write_string("%-------- Predicates --------\n\n", !IO),
    write_indent(Indent, !IO),
    map.keys(PredTable, PredIds),
    list.foldl(maybe_write_pred(Info, Indent, ModuleInfo, PredTable), PredIds,
        !IO).

:- pred maybe_write_pred(hlds_out_info::in, int::in, module_info::in,
    pred_table::in, pred_id::in, io::di, io::uo) is det.

maybe_write_pred(Info, Indent, ModuleInfo, PredTable, PredId, !IO) :-
    DumpOptions = Info ^ hoi_dump_hlds_options,
    DumpPredIdStrs = Info ^ hoi_dump_hlds_pred_ids,
    DumpPredNames = Info ^ hoi_dump_hlds_pred_names,
    pred_id_to_int(PredId, PredIdInt),
    map.lookup(PredTable, PredId, PredInfo),
    (
        % If the user requested one or more predicates/functions to be dumped,
        % we dump them even if the condition of the nested if-then-else below
        % would say they shouldn't be dumped, and we don't dump anything else.
        ( DumpPredIdStrs = [_ | _]
        ; DumpPredNames = [_ | _]
        )
    ->
        (
            (
                some [DumpPredIdStr, DumpPredId] (
                    list.member(DumpPredIdStr, DumpPredIdStrs),
                    string.to_int(DumpPredIdStr, DumpPredId),
                    PredIdInt = DumpPredId
                )
            ;
                PredName = pred_info_name(PredInfo),
                list.member(PredName, DumpPredNames)
            )
        ->
            write_pred(Info, Indent, ModuleInfo, PredId, PredInfo, !IO)
        ;
            true
        )
    ;
        (
            (
                \+ string.contains_char(DumpOptions, 'I'),
                pred_info_is_imported(PredInfo)
            ;
                % For pseudo-imported predicates (i.e. unification preds),
                % only print them if we are using a local mode for them.
                \+ string.contains_char(DumpOptions, 'I'),
                pred_info_is_pseudo_imported(PredInfo),
                ProcIds = pred_info_procids(PredInfo),
                hlds_pred.in_in_unification_proc_id(ProcId),
                ProcIds = [ProcId]
            ;
                % We dump unification and other compiler-generated special
                % predicates if suboption 'U' is on. We don't need that
                % information to understand how the program has been
                % transformed.
                \+ string.contains_char(DumpOptions, 'U'),
                is_unify_or_compare_pred(PredInfo)
            )
        ->
            true
        ;
            write_pred(Info, Indent, ModuleInfo, PredId, PredInfo, !IO)
        )
    ).

%-----------------------------------------------------------------------------%
%
% Write out a promise.
%

write_promise(Info, PromiseType, Indent, ModuleInfo, _PredId, VarSet,
        AppendVarNums, HeadVars, _PredOrFunc, Clause, TypeQual, !IO) :-
    % Curry the varset for term_io.write_variable/4.
    PrintVar = (pred(VarName::in, IOState0::di, IOState::uo) is det :-
        term_io.write_variable(VarName, VarSet, IOState0, IOState)
    ),

    write_indent(Indent, !IO),

    % Print initial formatting differently for assertions.
    (
        PromiseType = promise_type_true,
        io.write_string(":- promise all [", !IO),
        io.write_list(HeadVars, ", ", PrintVar, !IO),
        io.write_string("] (\n", !IO)
    ;
        ( PromiseType = promise_type_exclusive
        ; PromiseType = promise_type_exhaustive
        ; PromiseType = promise_type_exclusive_exhaustive
        ),
        io.write_string(":- all [", !IO),
        io.write_list(HeadVars, ", ", PrintVar, !IO),
        io.write_string("]", !IO),
        mercury_output_newline(Indent, !IO),
        prog_out.write_promise_type(PromiseType, !IO),
        mercury_output_newline(Indent, !IO),
        io.write_string("(\n", !IO)
    ),

    Clause = clause(_Modes, Goal, _Lang, _Context),
    do_write_goal(Info, Goal, ModuleInfo, VarSet, AppendVarNums,
        Indent+1, ").\n", TypeQual, !IO).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "hlds_out_module.m".

%-----------------------------------------------------------------------------%
:- end_module hlds.hlds_out.hlds_out_module.
%-----------------------------------------------------------------------------%