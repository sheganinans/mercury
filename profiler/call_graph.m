
%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
%
% call_graph.m
%
% Main author: petdr.
%
% Responsible for building the static call graph.  The dynamic call graph is
% built during the processing of 'Prof.CallPair', if the appropiate option is
% set.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module call_graph.

:- interface.

:- import_module relation, io.

:- pred call_graph__main(list(string), relation(string), relation(string),
							io__state, io__state).
:- mode call_graph__main(in, in, out, di, uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module read.
:- import_module options, globals.
:- import_module list, require, std_util.


call_graph__main(Args, StaticCallGraph0, StaticCallGraph) -->
	globals__io_lookup_bool_option(dynamic_cg, Dynamic),
	globals__io_lookup_bool_option(very_verbose, VeryVerbose),
	(
		{ Dynamic = yes } 
	->
		{ StaticCallGraph = StaticCallGraph0 }
	;
		build_static_call_graph(Args, StaticCallGraph0, VeryVerbose,
								StaticCallGraph)
	).


% build_static_call_graph:
% 	Build's the static call graph located in the *.prof files.
%
:- pred build_static_call_graph(list(string), relation(string), bool,
					relation(string), io__state, io__state).
:- mode build_static_call_graph(in, in, in, out, di, uo) is det.

build_static_call_graph([], StaticCallGraph, _, StaticCallGraph) --> []. 
build_static_call_graph([File | Files], StaticCallGraph0, VeryVerbose, 
							StaticCallGraph) -->
	maybe_write_string(VeryVerbose, "\n\tProcessing "),
	maybe_write_string(VeryVerbose, File),
	maybe_write_string(VeryVerbose, "..."),
	process_prof_file(File, StaticCallGraph0, StaticCallGraph1),
	maybe_write_string(VeryVerbose, " done"),
	build_static_call_graph(Files, StaticCallGraph1, VeryVerbose,
							StaticCallGraph).
	
		
% process_prof_file:
%	Put's all the Caller and Callee label pairs from File into the 
%	static call graph relation.
%
:- pred process_prof_file(string, relation(string), relation(string),
							io__state, io__state).
:- mode process_prof_file(in, in, out, di, uo) is det.

process_prof_file(File, StaticCallGraph0, StaticCallGraph) -->
	io__see(File, Result),
	(
		{ Result = ok },
		process_prof_file_2(StaticCallGraph0, StaticCallGraph),
		io__seen
	;
		{ Result = error(Error) },
		{ StaticCallGraph = StaticCallGraph0 },

		io__seen,
		{ io__error_message(Error, ErrorMsg) },
		io__write_string(ErrorMsg),
		io__write_string("\n")
	).

:- pred process_prof_file_2(relation(string), relation(string), 
							io__state, io__state).
:- mode process_prof_file_2(in, out, di, uo) is det.

process_prof_file_2(StaticCallGraph0, StaticCallGraph) -->
	maybe_read_label_name(MaybeLabelName),
	(
		{ MaybeLabelName = yes(CallerLabel) },
		read_label_name(CalleeLabel),
		{ relation__add(StaticCallGraph0, CallerLabel, CalleeLabel,
							StaticCallGraph1) },
		process_prof_file_2(StaticCallGraph1, StaticCallGraph)
	;
		{ MaybeLabelName = no },
		{ StaticCallGraph = StaticCallGraph0 }
	).


%-----------------------------------------------------------------------------%
