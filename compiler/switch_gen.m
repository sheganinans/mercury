%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
%
%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- module switch_gen.

:- interface.

:- import_module hlds, llds, code_gen, code_info, code_util.

:- pred switch_gen__generate_det_switch(var, list(case),
					code_tree, code_info, code_info).
:- mode switch_gen__generate_det_switch(in, in, out, in, out) is det.

:- pred switch_gen__generate_semi_switch(var, category, list(case),
					code_tree, code_info, code_info).
:- mode switch_gen__generate_semi_switch(in, in, in, out, in, out) is det.

:- pred switch_gen__generate_non_switch(var, category, list(case),
					code_tree, code_info, code_info).
:- mode switch_gen__generate_non_switch(in, in, in, out, in, out) is det.

%---------------------------------------------------------------------------%
:- implementation.

:- import_module unify_gen.

:- import_module tree, list, map, std_util, require.

	% To generate a deterministic switch, first we flush the
	% variable on whose tag we are going to switch, then we
	% generate the cases for the switch.

switch_gen__generate_det_switch(CaseVar, Cases, Instr) -->
	code_info__produce_variable(CaseVar, VarCode, _Lval),
	code_info__get_next_label(EndLabel),
	switch_gen__generate_det_cases(Cases, CaseVar, 
					EndLabel, CasesCode),
	{ Instr = tree(VarCode, CasesCode) },
	code_info__remake_with_store_map.

	% To generate a case for a deterministic switch we generate
	% code to do a tag-test and fall through to the next case in
	% the event of failure. The bodies of the cases are deterministic
	% so we generate them as such.
	%
	% Each case except the last consists of a tag test, followed by
	% the goal for that case, followed by a branch to the end of
	% the switch. The goal is generated as a "forced" goal which
	% ensures that all variables which are live at the end of the
	% case get stored in their stack slot.  For the last case, we
	% don't need to generate the tag test or the branch to the end
	% of the switch.  After the last case, we put the end-of-switch
	% label which other cases branch to after their case goals.

:- pred switch_gen__generate_det_cases(list(case), var, label,
					code_tree, code_info, code_info).
:- mode switch_gen__generate_det_cases(in, in, in, out, in, out) is det.

switch_gen__generate_det_cases([], _Var, _EndLabel, _Code) -->
		% should never be reached
	{ error("switch_gen__generate_det_cases: empty switch") }.

switch_gen__generate_det_cases([case(Cons, Goal)|Cases], Var, EndLabel,
								CasesCode) -->
	( { Cases = [] } ->
		code_gen__generate_forced_det_goal(Goal, ThisCode),
		{ EndCode = node([label(EndLabel) - "End of det switch"]) },
		{ CasesCode = tree(ThisCode, EndCode) }
	;
		code_info__grab_code_info(CodeInfo),
		code_info__get_next_label(ElseLab),
		code_info__push_failure_cont(yes(ElseLab)),
		unify_gen__generate_tag_rval(Var, Cons, Rval, FlushCode),
		code_info__generate_test_and_fail(Rval, BranchCode),
		code_info__pop_failure_cont,
		{ TestCode = tree(FlushCode, BranchCode) },
			% generate the case as a deterministic goal
		code_gen__generate_forced_det_goal(Goal, ThisCode),
		{ ElseLabel = node([
			goto(EndLabel) - "skip to the end of the det switch",
			label(ElseLab) - "next case"
		]) },
			% generate the rest of the cases.
		code_info__slap_code_info(CodeInfo),
		switch_gen__generate_det_cases(Cases, Var, EndLabel,
			CasesCode0),
		{ CasesCode = tree(tree(TestCode, ThisCode),
				tree(ElseLabel, CasesCode0)) }
	).

%---------------------------------------------------------------------------%

	% A semideterministic switch contains semideterministic goals.

switch_gen__generate_semi_switch(CaseVar, Det, Cases, Instr) -->
	code_info__produce_variable(CaseVar, VarCode, _Lval),
	code_info__get_next_label(EndLabel),
	switch_gen__generate_semi_cases(Cases, CaseVar, Det,
						EndLabel, CasesCode),
	{ Instr = tree(VarCode, CasesCode) },
	code_info__remake_with_store_map.

:- pred switch_gen__generate_semi_cases(list(case), var, category, label,
					code_tree, code_info, code_info).
:- mode switch_gen__generate_semi_cases(in, in, in, in, out, in, out)
	is det.

	% At the end of a locally semidet switch, we fail because we
	% came across a tag which was not covered by one of the cases.
	% It is followed by the end of switch label to which the cases
	% branch.

switch_gen__generate_semi_cases([], _Var, Det, EndLabel, Code) -->
	( { Det = semideterministic } ->
		code_info__generate_failure(FailCode)
	;
		{ FailCode = empty }
	),
	{ Code = tree(FailCode, node([ label(EndLabel) -
		"End of semidet switch" ])) }.

	% A semidet cases consists of a tag-test followed by a semidet
	% goal and a label for the start of the next case.
switch_gen__generate_semi_cases([case(Cons, Goal)|Cases], Var, Det, 
				EndLabel, CasesCode) -->
	(
		{ Cases = [_|_] ; Det = semideterministic }
	->
		code_info__grab_code_info(CodeInfo),
		code_info__get_next_label(ElseLab),
		code_info__push_failure_cont(yes(ElseLab)),
		unify_gen__generate_tag_rval(Var, Cons, Rval, FlushCode),
		code_info__generate_test_and_fail(Rval, BranchCode),
		code_info__pop_failure_cont,
		{ TestCode = tree(FlushCode, BranchCode) },
			% generate the case as a semi-deterministc goal
		code_gen__generate_forced_semi_goal(Goal, ThisCode),
		{ ElseLabel = node([
			goto(EndLabel) -
				"skip to the end of the semidet switch",
			label(ElseLab) - "next case"
		]) },
		{ ThisCaseCode = tree(tree(TestCode, ThisCode), ElseLabel) },
		% If there are more cases, the we need to restore
		% the expression cache, etc.
		( { Cases = [_|_] } ->
			code_info__slap_code_info(CodeInfo)
		;
			[]
		)
	;
			% generate the case as a semi-deterministc goal
		code_gen__generate_forced_semi_goal(Goal, ThisCaseCode)
	),
		% generate the rest of the cases.
	switch_gen__generate_semi_cases(Cases, Var, Det, EndLabel,
		CasesCode0),
	{ CasesCode = tree(ThisCaseCode, CasesCode0) }.

%---------------------------------------------------------------------------%

switch_gen__generate_non_switch(CaseVar, Det, Cases, Instr) -->
	code_info__produce_variable(CaseVar, VarCode, _Lval),
	code_info__get_next_label(EndLabel),
	switch_gen__generate_non_cases(Cases, CaseVar, Det, 
						EndLabel, CasesCode),
	{ Instr = tree(VarCode, CasesCode) },
	code_info__remake_with_store_map.

:- pred switch_gen__generate_non_cases(list(case), var, category, label,
					code_tree, code_info, code_info).
:- mode switch_gen__generate_non_cases(in, in, in, in, out, in, out) is det.

	% At the end of the switch, we fail because we came across a
	% tag which was not covered by one of the cases. It is followed
	% by the end of switch label to which the cases branch.
switch_gen__generate_non_cases([], _Var, Det, EndLabel, Code) -->
	( { Det = semideterministic } ->
		code_info__generate_failure(FailCode)
	;
		{ FailCode = empty }
	),
	{ Code = tree(FailCode, node([ label(EndLabel) -
		"End of nondet switch" ])) }.

	% A nondet cases consists of a tag-test followed by a nondet
	% goal and a label for the start of the next case.
switch_gen__generate_non_cases([case(Cons, Goal)|Cases], Var, Det, 
					EndLabel, CasesCode) -->
	(
		{ Cases = [_|_] ; Det = semideterministic }
	->
		code_info__grab_code_info(CodeInfo),
		code_info__get_next_label(ElseLab),
		code_info__push_failure_cont(yes(ElseLab)),
		unify_gen__generate_tag_rval(Var, Cons, Rval, FlushCode),
		code_info__generate_test_and_fail(Rval, BranchCode),
		code_info__pop_failure_cont,
		{ TestCode = tree(FlushCode, BranchCode) },
			% generate the case as a non-deterministc goal
		code_gen__generate_forced_non_goal(Goal, ThisCode),
		{ ElseLabel = node([
			goto(EndLabel) - "skip to the end of the nondet switch",
			label(ElseLab) - "next case"
		]) },
		{ ThisCaseCode = tree(tree(TestCode, ThisCode), ElseLabel) },
		% If there are more cases, the we need to restore
		% the expression cache, etc.
		( { Cases = [_|_] } ->
			code_info__slap_code_info(CodeInfo)
		;
			[]
		)
	;
			% generate the case as a non-deterministc goal
		code_gen__generate_forced_non_goal(Goal, ThisCaseCode)
	),
		% generate the rest of the cases.
	switch_gen__generate_non_cases(Cases, Var, Det, EndLabel,
		CasesCode0),
	{ CasesCode = tree(ThisCaseCode, CasesCode0) }.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
