%----------------------------------------------------------------------------%
% Copyright (C) 1997-2001, 2003 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%----------------------------------------------------------------------------%
%
% termination.m
%
% Main author: crs.
% Significant modifications by zs.
%
% This termination analysis is based on the algorithm given by Gerhard Groeger
% and Lutz Plumer in their paper "Handling of Mutual Recursion in Automatic 
% Termination Proofs for Logic Programs"  which was printed in JICSLP '92
% (the proceedings of the Joint International Conference and Symposium on
% Logic Programming 1992) pages 336 - 350.  
%
% Details about this implementation are covered in:
% Chris Speirs, Zoltan Somogyi, and Harald Sondergaard. Termination
% analysis for Mercury. In P. Van Hentenryck, editor, Static Analysis:
% Proceedings of the 4th International Symposium, Lecture Notes in Computer
% Science. Springer, 1997.  A more detailed version is available for
% download from http://www.cs.mu.oz.au/publications/tr_db/mu_97_09.ps.gz
%
% Currently, this implementation assumes that all c_code terminates.
% It also fails to prove termination for any predicate that involves higher
% order calls.
%
% The termination analysis may use a number of different norms to calculate 
% the size of a term.  These are set by using the --termination-norm string
% option.  To add a new norm, the following files must be modified:
%
% globals.m 		To change the termination_norm type and
% 			convert_termination_norm predicate.
%
% handle_options.m 	To change the error message that is produced when
% 			an incorrect argument is given to --termination-norm.
%
% term_norm.m		To change the functor_norm predicate and change the
% 			functor_alg type.
%
% termination.m		To change the set_functor_info predicate.
% 			
%----------------------------------------------------------------------------%

:- module transform_hlds__termination.

:- interface.

:- import_module hlds__hlds_module.
:- import_module hlds__hlds_pred.
:- import_module parse_tree__prog_data.
:- import_module transform_hlds__term_util.

:- import_module io, bool, std_util, list.

	% Perform termination analysis on the module.

:- pred termination__pass(module_info::in, module_info::out,
	io__state::di, io__state::uo) is det.

	% Write the given arg size info; verbose if the second arg is yes.

:- pred termination__write_maybe_arg_size_info(maybe(arg_size_info)::in,
	bool::in, io__state::di, io__state::uo) is det.

	% Write the given termination info; verbose if the second arg is yes.

:- pred termination__write_maybe_termination_info(maybe(termination_info)::in,
	bool::in, io__state::di, io__state::uo) is det.

	% Write out a termination_info pragma for the predicate if it
	% is exported, it is not a builtin and it is not a predicate used
	% to force type specialization.
:- pred termination__write_pred_termination_info(module_info, pred_id,
	io__state, io__state).
:- mode termination__write_pred_termination_info(in, in, di, uo) is det.

	% This predicate outputs termination_info pragmas;
	% such annotations can be part of .opt and .trans_opt files.

:- pred termination__write_pragma_termination_info(pred_or_func::in,
	sym_name::in, list(mode)::in, prog_context::in,
	maybe(arg_size_info)::in, maybe(termination_info)::in,
	io__state::di, io__state::uo) is det.

%----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds__inst_match.
:- import_module check_hlds__mode_util.
:- import_module check_hlds__type_util.
:- import_module hlds__error_util.
:- import_module hlds__hlds_data.
:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_out.
:- import_module hlds__passes_aux.
:- import_module hlds__special_pred.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module parse_tree__mercury_to_mercury.
:- import_module parse_tree__modules.
:- import_module parse_tree__prog_out.
:- import_module parse_tree__prog_util.
:- import_module transform_hlds__dependency_graph.
:- import_module transform_hlds__term_errors.
:- import_module transform_hlds__term_norm.
:- import_module transform_hlds__term_pass1.
:- import_module transform_hlds__term_pass2.

:- import_module map, int, char, string, relation.
:- import_module require, bag, set, term.
:- import_module varset.

%----------------------------------------------------------------------------%

termination__pass(Module0, Module) -->

		% Find out what norm we should use, and set up for using it
	globals__io_get_termination_norm(TermNorm),
	{ set_functor_info(TermNorm, Module0, FunctorInfo) },
	globals__io_lookup_int_option(termination_error_limit, MaxErrors),
	globals__io_lookup_int_option(termination_path_limit, MaxPaths),
	{ PassInfo = pass_info(FunctorInfo, MaxErrors, MaxPaths) },

		% Process builtin and compiler-generated predicates,
		% and user-supplied pragmas.
	{ module_info_predids(Module0, PredIds) },
	check_preds(PredIds, Module0, Module1),

		% Process all the SCCs of the call graph in a bottom up order.
	{ module_info_ensure_dependency_info(Module1, Module2) },
	{ module_info_dependency_info(Module2, DepInfo) },
	{ hlds_dependency_info_get_dependency_ordering(DepInfo, SCCs) },
		
		% Ensure that termination pragmas for a proc. do conflict
		% with termination pragmas for other procs. in the same SCC. 
	check_pragmas_are_consistent(SCCs, Module2, Module3),
	
	termination__process_all_sccs(SCCs, Module3, PassInfo, Module),

	globals__io_lookup_bool_option(make_optimization_interface,
		MakeOptInt),
	( { MakeOptInt = yes } ->
		termination__make_opt_int(PredIds, Module)
	;
		[]
	).

%----------------------------------------------------------------------------%
% Check that any user-supplied termination information (from pragma
% terminates/does_not_terminate) is consistent for each SCC in the program.
% 
% The information will not be consistent if:
% (1) One or more procs. in the SCC has a terminates pragma *and* one or more
%     procs. in the SCC has a does_not_terminate pragma.
% (2) One or more procs. in the SCC has a termination pragma (of either sort),
%     *and* the termination status of one or more procs. in the SCC is 
%     unknown.  (We check this after checking for the first case, so the
%     termination info. for the known procs. will be consistent.)
%
% In the first case set the termination for all procs. in the SCC to 
% can_loop and emit a warning.  In the second, set the termination of any
% procs. whose termination status is unknown to be the same as those whose
% termination status is known.

:- pred check_pragmas_are_consistent(list(list(pred_proc_id)), module_info,
	module_info, io__state, io__state).
:- mode check_pragmas_are_consistent(in, in, out, di, uo) is det.

check_pragmas_are_consistent(SCCs, Module0, Module) -->
	list__foldl2(check_scc_pragmas_are_consistent, SCCs, Module0, Module).

:- pred check_scc_pragmas_are_consistent(list(pred_proc_id), module_info, 
	module_info, io__state, io__state).
:- mode check_scc_pragmas_are_consistent(in, in, out, di, uo) is det.

check_scc_pragmas_are_consistent(SCC, Module0, Module, !IO) :-
	list__filter(is_termination_known(Module0), SCC, SCCTerminationKnown, 
		SCCTerminationUnknown),
	( 
		SCCTerminationKnown = [],
		Module = Module0
	;
		SCCTerminationKnown = [KnownPPId | _],
		module_info_pred_proc_info(Module0, KnownPPId, _, 
			KnownProcInfo),
		proc_info_get_maybe_termination_info(KnownProcInfo, 
			MaybeKnownTerm),
		( 
			MaybeKnownTerm = no,
			unexpected(this_file, "No termination info. found.")
		;
			MaybeKnownTerm  = yes(KnownTermStatus)
		),
		( 
			check_procs_known_term(KnownTermStatus, 
				SCCTerminationKnown, Module0)
		->
			    % Force any procs. in the SCC whose termination 
			    % status is unknown to have the same termination 
			    % status as those that are known.
			set_termination_infos(SCCTerminationUnknown, 
				KnownTermStatus, Module0, Module)
		;
			    % There is a conflict between the user-supplied 
			    % termination information for two or more procs. 
			    % in this SCC.  Emit a warning and then assume 
			    % that they all loop.
			get_context_from_scc(SCCTerminationKnown, Module0, 
				Context),
			NewTermStatus = 
				can_loop([Context - inconsistent_annotations]),
			set_termination_infos(SCC, NewTermStatus, Module0, 
				Module),
			
			PredIds = list__map((func(proc(PredId, _)) = PredId), 
				SCCTerminationKnown),
			error_util__describe_several_pred_names(Module, 
				PredIds, PredNames),	
			Piece1 = words(
				"are mutually recursive but some of their"),
			Piece2 = words(
				"termination pragmas are inconsistent."), 
			Components = [words("Warning:")] ++ PredNames ++ 
				[Piece1, Piece2],
			error_util__report_warning(Context, 0, Components, !IO)
		)	
	).		

	% Check that all procedures in an SCC whose termination status is known
	% have the same termination status. 
:- pred check_procs_known_term(termination_info, list(pred_proc_id), 
	module_info). 
:- mode check_procs_known_term(in, in, in) is semidet.

check_procs_known_term(_, [], _).
check_procs_known_term(Status, [PPId | PPIds], ModuleInfo) :-
	module_info_pred_proc_info(ModuleInfo, PPId, _, ProcInfo),
	proc_info_get_maybe_termination_info(ProcInfo, MaybeTerm),
	(
		MaybeTerm = no,		
		unexpected(this_file, "No termination info for procedure.")
	;
		MaybeTerm = yes(PPIdStatus)
	),
	(
		Status = cannot_loop,
		PPIdStatus = cannot_loop
	;
		Status = can_loop(_),
		PPIdStatus = can_loop(_)
	),
	check_procs_known_term(Status, PPIds, ModuleInfo).

	% Succeeds iff the termination status of a procedure is known.
:- pred is_termination_known(module_info, pred_proc_id).
:- mode is_termination_known(in, in) is semidet.

is_termination_known(Module, PPId) :-
	module_info_pred_proc_info(Module, PPId, _, ProcInfo),
	proc_info_get_maybe_termination_info(ProcInfo, yes(_)).	

%----------------------------------------------------------------------------%

:- pred termination__process_all_sccs(list(list(pred_proc_id)), module_info,
	pass_info, module_info, io__state, io__state).
:- mode termination__process_all_sccs(in, in, in, out, di, uo) is det.

termination__process_all_sccs([], Module, _, Module) --> [].
termination__process_all_sccs([SCC | SCCs], Module0, PassInfo, Module) -->
	termination__process_scc(SCC, Module0, PassInfo, Module1),
	termination__process_all_sccs(SCCs, Module1, PassInfo, Module).

	% For each SCC, we first find out the relationships among
	% the sizes of the arguments of the procedures of the SCC,
	% and then attempt to prove termination of the procedures.

:- pred termination__process_scc(list(pred_proc_id), module_info, pass_info,
	module_info, io__state, io__state).
:- mode termination__process_scc(in, in, in, out, di, uo) is det.

termination__process_scc(SCC, Module0, PassInfo, Module) -->
	{ IsArgSizeKnown = (pred(PPId::in) is semidet :- 
		PPId = proc(PredId, ProcId),
		module_info_pred_proc_info(Module0, PredId, ProcId,
			_, ProcInfo),
		proc_info_get_maybe_arg_size_info(ProcInfo, yes(_))
	) },
	{ list__filter(IsArgSizeKnown, SCC,
		_SCCArgSizeKnown, SCCArgSizeUnknown) },
	( { SCCArgSizeUnknown = [] } ->
		{ ArgSizeErrors = [] },
		{ TermErrors = [] },
		{ Module1 = Module0 }
	;
		find_arg_sizes_in_scc(SCCArgSizeUnknown, Module0, PassInfo,
			ArgSizeResult, TermErrors),
		{
			ArgSizeResult = ok(Solutions, OutputSupplierMap),
			set_finite_arg_size_infos(Solutions,
				OutputSupplierMap, Module0, Module1),
			ArgSizeErrors = []
		;
			ArgSizeResult = error(Errors),
			set_infinite_arg_size_infos(SCCArgSizeUnknown,
				infinite(Errors), Module0, Module1),
			ArgSizeErrors = Errors
		}
	),
	{ list__filter(is_termination_known(Module1), SCC,
		_SCCTerminationKnown, SCCTerminationUnknown) },
	( { SCCTerminationUnknown = [] } ->
			%
			% We may possibly have encountered inconsistent
			% terminates/does_not_terminate pragmas for this SCC,
			% so we need to report errors here as well.
		{ Module = Module1 }
	;
		{ IsFatal = (pred(ContextError::in) is semidet :-
			ContextError = _Context - Error,
			( Error = horder_call
			; Error = horder_args(_, _)
			; Error = imported_pred
			)
		) },
		{ list__filter(IsFatal, ArgSizeErrors, FatalErrors) },
		{ list__append(TermErrors, FatalErrors, BothErrors) },
		( { BothErrors = [_ | _] } ->
			% These errors prevent pass 2 from proving termination
			% in any case, so we may as well not prove it quickly.
			{ PassInfo = pass_info(_, MaxErrors, _) },
			{ list__take_upto(MaxErrors, BothErrors,
				ReportedErrors) },
			{ TerminationResult = can_loop(ReportedErrors) }
		;
			globals__io_lookup_int_option(termination_single_args,
				SingleArgs),
			{ prove_termination_in_scc(SCCTerminationUnknown,
				Module1, PassInfo, SingleArgs,
				TerminationResult) }
		),
		{ set_termination_infos(SCCTerminationUnknown,
			TerminationResult, Module1, Module2) },
		( { TerminationResult = can_loop(TerminationErrors) } -> 
			report_termination_errors(SCC, TerminationErrors, 
				Module2, Module)
		;
			{ Module = Module2 }
		)
	).

%----------------------------------------------------------------------------%

% This predicate takes the results from solve_equations
% and inserts these results into the module info.

:- pred set_finite_arg_size_infos(list(pair(pred_proc_id, int))::in,
	used_args::in, module_info::in, module_info::out) is det.

set_finite_arg_size_infos([], _, Module, Module).
set_finite_arg_size_infos([Soln | Solns], OutputSupplierMap, Module0, Module) :-
	Soln = PPId - Gamma,
	PPId = proc(PredId, ProcId),
	module_info_preds(Module0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo),
	pred_info_procedures(PredInfo, ProcTable),
	map__lookup(ProcTable, ProcId, ProcInfo),
	map__lookup(OutputSupplierMap, PPId, OutputSuppliers),
	ArgSizeInfo = finite(Gamma, OutputSuppliers),
	proc_info_set_maybe_arg_size_info(yes(ArgSizeInfo),
		ProcInfo, ProcInfo1),
	map__set(ProcTable, ProcId, ProcInfo1, ProcTable1),
	pred_info_set_procedures(ProcTable1, PredInfo, PredInfo1),
	map__set(PredTable0, PredId, PredInfo1, PredTable),
	module_info_set_preds(Module0, PredTable, Module1),
	set_finite_arg_size_infos(Solns, OutputSupplierMap, Module1, Module).

:- pred set_infinite_arg_size_infos(list(pred_proc_id)::in,
	arg_size_info::in, module_info::in, module_info::out) is det.

set_infinite_arg_size_infos([], _, Module, Module).
set_infinite_arg_size_infos([PPId | PPIds], ArgSizeInfo, Module0, Module) :-
	PPId = proc(PredId, ProcId),
	module_info_preds(Module0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo),
	pred_info_procedures(PredInfo, ProcTable),
	map__lookup(ProcTable, ProcId, ProcInfo),
	proc_info_set_maybe_arg_size_info(yes(ArgSizeInfo),
		ProcInfo, ProcInfo1),
	map__set(ProcTable, ProcId, ProcInfo1, ProcTable1),
	pred_info_set_procedures(ProcTable1, PredInfo, PredInfo1),
	map__set(PredTable0, PredId, PredInfo1, PredTable),
	module_info_set_preds(Module0, PredTable, Module1),
	set_infinite_arg_size_infos(PPIds, ArgSizeInfo, Module1, Module).

%----------------------------------------------------------------------------%

:- pred set_termination_infos(list(pred_proc_id)::in, termination_info::in,
	module_info::in, module_info::out) is det.

set_termination_infos([], _, Module, Module).
set_termination_infos([PPId | PPIds], TerminationInfo, Module0, Module) :-
	PPId = proc(PredId, ProcId),
	module_info_preds(Module0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, ProcTable0),
	map__lookup(ProcTable0, ProcId, ProcInfo0),
	proc_info_set_maybe_termination_info(yes(TerminationInfo),
		ProcInfo0, ProcInfo),
	map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable),
	pred_info_set_procedures(ProcTable, PredInfo0, PredInfo),
	map__det_update(PredTable0, PredId, PredInfo, PredTable),
	module_info_set_preds(Module0, PredTable, Module1),
	set_termination_infos(PPIds, TerminationInfo, Module1, Module).

:- pred report_termination_errors(list(pred_proc_id)::in,
	list(term_errors__error)::in, module_info::in, module_info::out,
	io__state::di, io__state::uo) is det.

report_termination_errors(SCC, Errors, Module0, Module) -->
	globals__io_lookup_bool_option(check_termination,
		NormalErrors),
	globals__io_lookup_bool_option(verbose_check_termination,
		VerboseErrors),
	( 
		{ IsCheckTerm = lambda([PPId::in] is semidet, (
			PPId = proc(PredId, ProcId),
			module_info_pred_proc_info(Module0, PredId, ProcId,
				PredInfo, _),
			\+ pred_info_is_imported(PredInfo),
			pred_info_get_markers(PredInfo, Markers),
			check_marker(Markers, check_termination)
		)) },
		{ list__filter(IsCheckTerm, SCC, CheckTermPPIds) },
		{ CheckTermPPIds = [_ | _] }
	->
		% If any procedure in the SCC has a check_terminates pragma,
		% print out one error message for the whole SCC and indicate
		% an error.
		term_errors__report_term_errors(SCC, Errors, Module0),
		io__set_exit_status(1),
		{ module_info_incr_errors(Module0, Module) }
	;
		{ IsNonImported = lambda([PPId::in] is semidet, (
			PPId = proc(PredId, ProcId),
			module_info_pred_proc_info(Module0, PredId, ProcId,
				PredInfo, _),
			\+ pred_info_is_imported(PredInfo)
		)) },
		{ list__filter(IsNonImported, SCC, NonImportedPPIds) },
		{ NonImportedPPIds = [_ | _] },

		% Only output warnings of non-termination for
		% direct errors, unless verbose errors are
		% enabled.  Direct errors are errors where the
		% compiler analysed the code and was not able to
		% prove termination.  Indirect warnings are
		% created when code is used/called which the
		% compiler was unable to analyse/prove termination of.  
		{ VerboseErrors = yes ->
			PrintErrors = Errors
		; NormalErrors = yes ->
			IsNonSimple = lambda([ContextError::in] is semidet, (
				ContextError = _Context - Error,
				\+ indirect_error(Error)
			)),
			list__filter(IsNonSimple, Errors, PrintErrors)
		;
			fail
		}
	->
		term_errors__report_term_errors(SCC, PrintErrors, Module0),
		{ Module = Module0 }
	;
		{ Module = Module0 }
	).

%----------------------------------------------------------------------------%

:- pred check_preds(list(pred_id), module_info, module_info, 
	io__state, io__state).
:- mode check_preds(in, in, out, di, uo) is det.

% This predicate processes each predicate and sets the termination property
% if possible.  This is done as follows:  Set the termination to yes if:
% - there is a terminates pragma defined for the predicate
% - there is a `check_termination' pragma defined for the predicate, and it
% 	is imported, and the compiler is not currently generating the
% 	intermodule optimization file.
% - the predicate is a builtin predicate or is compiler generated (This
% 	also sets the termination constant and UsedArgs).
%
% Set the termination to dont_know if:
% - there is a `does_not_terminate' pragma defined for this predicate.
% - the predicate is imported and there is no other source of information
% 	about it (termination_info pragmas, terminates pragmas,
% 	check_termination pragmas, builtin/compiler generated).

check_preds([], Module, Module, State, State).
check_preds([PredId | PredIds] , Module0, Module, State0, State) :-
	write_pred_progress_message("% Checking ", PredId, Module0,
		State0, State1),
	globals__io_lookup_bool_option(make_optimization_interface,
		MakeOptInt, State1, State2),
	module_info_preds(Module0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_import_status(PredInfo0, ImportStatus),
	pred_info_context(PredInfo0, Context),
	pred_info_procedures(PredInfo0, ProcTable0),
	pred_info_get_markers(PredInfo0, Markers),
	ProcIds = pred_info_procids(PredInfo0),
	( 
		% It is possible for compiler generated/mercury builtin
		% predicates to be imported or locally defined, so they
		% must be covered here, separately.
		set_compiler_gen_terminates(PredInfo0, ProcIds, PredId,
			Module0, ProcTable0, ProcTable1)
	->
		ProcTable2 = ProcTable1
	;
		status_defined_in_this_module(ImportStatus, yes)
	->
		( check_marker(Markers, terminates) ->
			change_procs_termination_info(ProcIds, yes,
				cannot_loop, ProcTable0, ProcTable2)
		;
			ProcTable2 = ProcTable0
		)
	;
		% Not defined in this module.

		% All of the predicates that are processed in this section
		% are imported in some way.
		% With imported predicates, any 'check_termination'
		% pragmas will be checked by the compiler when it compiles
		% the relevant source file (that the predicate was imported
		% from).  When making the intermodule optimizations, the 
		% check_termination will not be checked when the relevant
		% source file is compiled, so it cannot be depended upon. 
		(
			(
				check_marker(Markers, terminates)
			; 
				MakeOptInt = no,
				check_marker(Markers, check_termination)
			)
		->
			change_procs_termination_info(ProcIds, yes,
				cannot_loop, ProcTable0, ProcTable1)
		;
			TerminationError = Context - imported_pred,
			TerminationInfo = can_loop([TerminationError]),
			change_procs_termination_info(ProcIds, no,
				TerminationInfo, ProcTable0, ProcTable1)
		),
		ArgSizeError = imported_pred,
		ArgSizeInfo = infinite([Context - ArgSizeError]),
		change_procs_arg_size_info(ProcIds, no, ArgSizeInfo,
			ProcTable1, ProcTable2)
	),
	( check_marker(Markers, does_not_terminate) ->
		RequestError = Context - does_not_term_pragma(PredId),
		RequestTerminationInfo = can_loop([RequestError]),
		change_procs_termination_info(ProcIds, yes,
			RequestTerminationInfo, ProcTable2, ProcTable)
	;
		ProcTable = ProcTable2
	),
	pred_info_set_procedures(ProcTable, PredInfo0, PredInfo),
	map__set(PredTable0, PredId, PredInfo, PredTable),
	module_info_set_preds(Module0, PredTable, Module1),
	check_preds(PredIds, Module1, Module, State2, State).

%----------------------------------------------------------------------------%

% This predicate checks each ProcId in the list to see if it is a compiler
% generated predicate, or a predicate from builtin.m or private_builtin.m.
% If it is, then the compiler sets the termination property of the ProcIds
% accordingly.

% XXX This does the wrong thing for calls to unify/2,
% which might not terminate in the case of user-defined equality predicates.

:- pred set_compiler_gen_terminates(pred_info, list(proc_id), pred_id,
	module_info, proc_table, proc_table).
:- mode set_compiler_gen_terminates(in, in, in, in, in, out) is semidet.

set_compiler_gen_terminates(PredInfo, ProcIds, PredId, Module,
		ProcTable0, ProcTable) :-
	(
		pred_info_is_builtin(PredInfo)
	->
		set_builtin_terminates(ProcIds, PredId, PredInfo, Module,
			ProcTable0, ProcTable)
	;
		(
			ModuleName = pred_info_module(PredInfo),
			Name = pred_info_name(PredInfo),
			Arity = pred_info_arity(PredInfo),
			special_pred_name_arity(SpecPredId0, Name, Arity),
			any_mercury_builtin_module(ModuleName)
		->
			SpecialPredId = SpecPredId0
		;
			pred_info_get_maybe_special_pred(PredInfo,
				MaybeSpecial),
			MaybeSpecial = yes(SpecialPredId - _)
		)
	->
		set_generated_terminates(ProcIds, SpecialPredId,
			ProcTable0, ProcTable)
	;
		fail
	).

:- pred set_generated_terminates(list(proc_id), special_pred_id,
	proc_table, proc_table).
:- mode set_generated_terminates(in, in, in, out) is det.

set_generated_terminates([], _, ProcTable, ProcTable).
set_generated_terminates([ProcId | ProcIds], SpecialPredId,
		ProcTable0, ProcTable) :-
	map__lookup(ProcTable0, ProcId, ProcInfo0),
	proc_info_headvars(ProcInfo0, HeadVars),
	special_pred_id_to_termination(SpecialPredId, HeadVars,
		ArgSize, Termination),
	proc_info_set_maybe_arg_size_info(yes(ArgSize), ProcInfo0, ProcInfo1),
	proc_info_set_maybe_termination_info(yes(Termination),
		ProcInfo1, ProcInfo),
	map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable1),
	set_generated_terminates(ProcIds, SpecialPredId,
		ProcTable1, ProcTable).

:- pred special_pred_id_to_termination(special_pred_id::in, 
	list(prog_var)::in, arg_size_info::out, termination_info::out) is det.

special_pred_id_to_termination(compare, HeadVars, ArgSize, Termination) :-
	term_util__make_bool_list(HeadVars, [no, no, no], OutList),
	ArgSize = finite(0, OutList),
	Termination = cannot_loop.
special_pred_id_to_termination(unify, HeadVars, ArgSize, Termination) :-
	term_util__make_bool_list(HeadVars, [yes, yes], OutList),
	ArgSize = finite(0, OutList),
	Termination = cannot_loop.
special_pred_id_to_termination(index, HeadVars, ArgSize, Termination) :-
	term_util__make_bool_list(HeadVars, [no, no], OutList),
	ArgSize = finite(0, OutList),
	Termination = cannot_loop.

% The list of proc_ids must refer to builtin predicates.  This predicate
% sets the termination information of builtin predicates.

:- pred set_builtin_terminates(list(proc_id), pred_id, pred_info, module_info, 
	proc_table, proc_table).
:- mode set_builtin_terminates(in, in, in, in, in, out) is det.

set_builtin_terminates([], _, _, _, ProcTable, ProcTable).
set_builtin_terminates([ProcId | ProcIds], PredId, PredInfo, Module,
		ProcTable0, ProcTable) :-
	map__lookup(ProcTable0, ProcId, ProcInfo0), 
	( all_args_input_or_zero_size(Module, PredInfo, ProcInfo0) ->
		% The size of the output arguments will all be 0,
		% independent of the size of the input variables.
		% UsedArgs should be set to yes([no, no, ...]).
		proc_info_headvars(ProcInfo0, HeadVars),
		term_util__make_bool_list(HeadVars, [], UsedArgs),
		ArgSizeInfo = yes(finite(0, UsedArgs))
	;
		pred_info_context(PredInfo, Context),
		Error = is_builtin(PredId),
		ArgSizeInfo = yes(infinite([Context - Error]))
	),
	proc_info_set_maybe_arg_size_info(ArgSizeInfo, ProcInfo0, ProcInfo1),
	proc_info_set_maybe_termination_info(yes(cannot_loop),
		ProcInfo1, ProcInfo),
	map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable1),
	set_builtin_terminates(ProcIds, PredId, PredInfo, Module,
		ProcTable1, ProcTable).

:- pred all_args_input_or_zero_size(module_info, pred_info, proc_info).
:- mode all_args_input_or_zero_size(in, in, in) is semidet.

all_args_input_or_zero_size(Module, PredInfo, ProcInfo) :-
	pred_info_arg_types(PredInfo, TypeList),
	proc_info_argmodes(ProcInfo, ModeList),
	all_args_input_or_zero_size_2(TypeList, ModeList, Module). 

:- pred all_args_input_or_zero_size_2(list(type), list(mode), module_info).
:- mode all_args_input_or_zero_size_2(in, in, in) is semidet.

all_args_input_or_zero_size_2([], [], _).
all_args_input_or_zero_size_2([], [_|_], _) :- 
	error("all_args_input_or_zero_size_2: Unmatched variables.").
all_args_input_or_zero_size_2([_|_], [], _) :- 
	error("all_args_input_or_zero_size_2: Unmatched variables").
all_args_input_or_zero_size_2([Type | Types], [Mode | Modes], Module) :-
	( mode_is_input(Module, Mode) ->
		% The variable is an input variables, so its size is
		% irrelevant.
		all_args_input_or_zero_size_2(Types, Modes, Module)
	;
		zero_size_type(Type, Module),
		all_args_input_or_zero_size_2(Types, Modes, Module)
	).

%----------------------------------------------------------------------------%

% This predicate sets the arg_size_info property of the given list
% of procedures.
%
% change_procs_arg_size_info(ProcList, Override, TerminationInfo,
% 		ProcTable, ProcTable)
%
% If Override is yes, then this predicate overrides any existing arg_size
% information. If Override is no, then it leaves the proc_info of a procedure
% unchanged unless the proc_info had no arg_size information (i.e. the
% maybe(arg_size_info) field was set to "no").

:- pred change_procs_arg_size_info(list(proc_id)::in, bool::in,
	arg_size_info::in, proc_table::in, proc_table::out) is det.

change_procs_arg_size_info([], _, _, ProcTable, ProcTable).
change_procs_arg_size_info([ProcId | ProcIds], Override, ArgSize,
		ProcTable0, ProcTable) :-
	map__lookup(ProcTable0, ProcId, ProcInfo0),
	( 
		( 
			Override = yes
		;
			proc_info_get_maybe_arg_size_info(ProcInfo0, no)
		)
	->
		proc_info_set_maybe_arg_size_info(yes(ArgSize),
			ProcInfo0, ProcInfo),
		map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable1)
	;
		ProcTable1 = ProcTable0
	),
	change_procs_arg_size_info(ProcIds, Override, ArgSize,
		ProcTable1, ProcTable).

% This predicate sets the termination_info property of the given list
% of procedures.
%
% change_procs_termination_info(ProcList, Override, TerminationInfo,
% 		ProcTable, ProcTable)
%
% If Override is yes, then this predicate overrides any existing termination
% information. If Override is no, then it leaves the proc_info of a procedure
% unchanged unless the proc_info had no termination information (i.e. the
% maybe(termination_info) field was set to "no").

:- pred change_procs_termination_info(list(proc_id)::in, bool::in,
	termination_info::in, proc_table::in, proc_table::out) is det.

change_procs_termination_info([], _, _, ProcTable, ProcTable).
change_procs_termination_info([ProcId | ProcIds], Override, Termination,
		ProcTable0, ProcTable) :-
	map__lookup(ProcTable0, ProcId, ProcInfo0),
	( 
		( 
			Override = yes
		;
			proc_info_get_maybe_termination_info(ProcInfo0, no)
		)
	->
		proc_info_set_maybe_termination_info(yes(Termination),
			ProcInfo0, ProcInfo),
		map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable1)
	;
		ProcTable1 = ProcTable0
	),
	change_procs_termination_info(ProcIds, Override, Termination,
		ProcTable1, ProcTable).

%----------------------------------------------------------------------------%
%----------------------------------------------------------------------------%

% These predicates are used to add the termination_info pragmas to the .opt
% file.  It is often better to use the .trans_opt file, as it gives
% much better accuracy.  The two files are not mutually exclusive, and
% termination information may be stored in both.

:- pred termination__make_opt_int(list(pred_id), module_info, io__state, 
		io__state).
:- mode termination__make_opt_int(in, in, di, uo) is det.

termination__make_opt_int(PredIds, Module) -->
	{ module_info_name(Module, ModuleName) },
	module_name_to_file_name(ModuleName, ".opt.tmp", no, OptFileName),
	globals__io_lookup_bool_option(verbose, Verbose),
	maybe_write_string(Verbose,
		"% Appending termination_info pragmas to `"),
	maybe_write_string(Verbose, OptFileName),
	maybe_write_string(Verbose, "'..."),
	maybe_flush_output(Verbose),

	io__open_append(OptFileName, OptFileRes),
	( { OptFileRes = ok(OptFile) },
		io__set_output_stream(OptFile, OldStream),
		list__foldl(termination__write_pred_termination_info(Module),
			PredIds),
		io__set_output_stream(OldStream, _),
		io__close_output(OptFile),
		maybe_write_string(Verbose, " done.\n")
	; { OptFileRes = error(IOError) },
		% failed to open the .opt file for processing
		maybe_write_string(Verbose, " failed!\n"),
		{ io__error_message(IOError, IOErrorMessage) },
		io__write_strings(["Error opening file `",
			OptFileName, "' for output: ", IOErrorMessage]),
		io__set_exit_status(1)
	).

termination__write_pred_termination_info(Module, PredId) -->
	{ module_info_pred_info(Module, PredId, PredInfo) },
	{ pred_info_import_status(PredInfo, ImportStatus) },
	{ module_info_type_spec_info(Module, TypeSpecInfo) },
	{ TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _) },

	( 
		{
			ImportStatus = exported
		;
			ImportStatus = opt_exported
		},
		{ \+ is_unify_or_compare_pred(PredInfo) },

		% XXX These should be allowed, but the predicate
		% declaration for the specialized predicate is not produced
		% before the termination pragmas are read in, resulting
		% in an undefined predicate error.
		\+ { set__member(PredId, TypeSpecForcePreds) }
	->
		{ PredName = pred_info_name(PredInfo) },
		{ ProcIds = pred_info_procids(PredInfo) },
		{ PredOrFunc = pred_info_is_pred_or_func(PredInfo) },
		{ ModuleName = pred_info_module(PredInfo) },
		{ pred_info_procedures(PredInfo, ProcTable) },
		{ pred_info_context(PredInfo, Context) },
		{ SymName = qualified(ModuleName, PredName) },
		termination__make_opt_int_procs(PredId, ProcIds, ProcTable, 
			PredOrFunc, SymName, Context)
	;
		[]
	).

:- pred termination__make_opt_int_procs(pred_id, list(proc_id), proc_table,
	pred_or_func, sym_name, prog_context, io__state, io__state).
:- mode termination__make_opt_int_procs(in, in, in, in, in, in, di, uo) is det.

termination__make_opt_int_procs(_PredId, [], _, _, _, _) --> [].
termination__make_opt_int_procs(PredId, [ ProcId | ProcIds ], ProcTable, 
		PredOrFunc, SymName, Context) -->
	{ map__lookup(ProcTable, ProcId, ProcInfo) },
	{ proc_info_get_maybe_arg_size_info(ProcInfo, ArgSize) },
	{ proc_info_get_maybe_termination_info(ProcInfo, Termination) },
	{ proc_info_declared_argmodes(ProcInfo, ModeList) },
	termination__write_pragma_termination_info(PredOrFunc, SymName,
		ModeList, Context, ArgSize, Termination),
	termination__make_opt_int_procs(PredId, ProcIds, ProcTable, 
		PredOrFunc, SymName, Context).

%----------------------------------------------------------------------------%

% These predicates are used to print out the termination_info pragmas.
% If they are changed, then prog_io_pragma.m must also be changed so that
% it can parse the resulting pragma termination_info declarations.

termination__write_pragma_termination_info(PredOrFunc, SymName,
		ModeList, Context, MaybeArgSize, MaybeTermination) -->
	io__write_string(":- pragma termination_info("),
	{ varset__init(InitVarSet) },
	( 
		{ PredOrFunc = predicate },
		mercury_output_pred_mode_subdecl(InitVarSet, SymName, 
			ModeList, no, Context)
	;
		{ PredOrFunc = function },
		{ pred_args_to_func_args(ModeList, FuncModeList, RetMode) },
		mercury_output_func_mode_subdecl(InitVarSet, SymName, 
			FuncModeList, RetMode, no, Context)
	),
	io__write_string(", "),
	termination__write_maybe_arg_size_info(MaybeArgSize, no),
	io__write_string(", "),
	termination__write_maybe_termination_info(MaybeTermination, no),
	io__write_string(").\n").

termination__write_maybe_arg_size_info(MaybeArgSizeInfo, Verbose) -->
	( 	
		{ MaybeArgSizeInfo = no },
		io__write_string("not_set") 
	;
		{ MaybeArgSizeInfo = yes(infinite(Error)) },
		io__write_string("infinite"),
		( { Verbose = yes } ->
			io__write_string("("),
			io__write(Error),
			io__write_string(")")
		;
			[]
		)
	;
		{ MaybeArgSizeInfo = yes(finite(Const, UsedArgs)) },
		io__write_string("finite("),
		io__write_int(Const),
		io__write_string(", "),
		termination__write_used_args(UsedArgs),
		io__write_string(")")
	).

:- pred termination__write_used_args(list(bool)::in,
	io__state::di, io__state::uo) is det.

termination__write_used_args([]) -->
	io__write_string("[]").
termination__write_used_args([UsedArg | UsedArgs]) -->
	io__write_string("["),
	io__write(UsedArg),
	termination__write_used_args_2(UsedArgs),
	io__write_string("]").

:- pred termination__write_used_args_2(list(bool)::in,
	io__state::di, io__state::uo) is det.

termination__write_used_args_2([]) --> [].
termination__write_used_args_2([ UsedArg | UsedArgs ]) -->
	io__write_string(", "),
	io__write(UsedArg),
	termination__write_used_args_2(UsedArgs).

termination__write_maybe_termination_info(MaybeTerminationInfo, Verbose) -->
	( 	
		{ MaybeTerminationInfo = no },
		io__write_string("not_set") 
	;
		{ MaybeTerminationInfo = yes(cannot_loop) },
		io__write_string("cannot_loop")
	;
		{ MaybeTerminationInfo = yes(can_loop(Error)) },
		io__write_string("can_loop"),
		( { Verbose = yes } ->
			io__write_string("("),
			io__write(Error),
			io__write_string(")")
		;
			[]
		)
	).

%----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "termination.m".
