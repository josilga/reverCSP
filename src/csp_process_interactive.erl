-module(csp_process_interactive).

-export([start/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Main interface
%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start(FirstProcess, PidInteraction) -> 
	FirstExp = 
		{agent_call,{src_span,0,0,0,0,0,0},FirstProcess,[]},
	execute_csp(FirstExp),
	send_message2regprocess(printer,{info_graph,get_self()}),
	InfoGraph = 
		receive 
			{info_graph, InfoGraph_} ->
				InfoGraph_
		after 
			1000 -> 
				{{{0,0,0,now()},"",""},{[],[]}}
		end,
	send_message2regprocess(printer,stop),
	InfoGraph.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%   Process Execution
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Intentar hace priemra aproximación sin canales. 

execute_csp(Exp) ->
	Questions = get_questions(Exp, []),
	io:get_line(standard_io, format("****State****\n~p\n****Options****\n~p\n************\n", [Exp, Questions])),
	case Questions of 
		[] ->
			ok;
		_ ->
			Answer = ask_questions(Questions),
			io:get_line(standard_io, format("****Answer****\n~p\n************\n", [Answer])),
			execute_csp(process_answer(Exp, Answer))
	end.

ask_questions(List) ->
	rand:seed(exs64),
	Selected = rand:uniform(length(List)),
	lists:nth(Selected, List).

% Para el Seq Comp las preguntas las sacamos del primer proceso. Cuando estemos procesando el segundo ya no habrá SC
% Cuando se llegue a ser skip el primer proceso entonces se quita. Igual debería de guardarse en un skip especial o algo así los nodos para saber a que tiene que unirse. i.e. process_answer({skip, SPAN}, _) -> SE DIBUJA SKIP y se devuelve {skip, SPAN, [nodo_skip]}.
% Cuando un paralslismo acaben los dos con {skip,_,_}, meter un {skip, SPAN, Nods_skip}.
% El SC cuando se encuntre que su primer proceso se evalue a esto, se unira a los acabados y desaparecerá
get_questions({prefix, SPAN1, Channels, Event, ProcessPrefixing, SPAN2}, Renamings) ->
	[{prefix,SPAN1,Channels,Event,ProcessPrefixing,SPAN2}];
get_questions({'|~|', PA, PB, SPAN}, Renamings) ->
	[{'|~|', PA, PB, SPAN}];
% El external choice se queda sempre que al processar les rames no cambien. Si cambien y el que s'ha llançat era un event (no tau o tick) aleshores llevem el external choice i deixem la rama que ha canviat.
get_questions({agent_call, SPAN, ProcessName, Arguments}, Renamings) ->
	[{agent_call, SPAN, ProcessName, Arguments}];
get_questions({'|||', PA, PB, SPAN}, Renamings) ->
	get_questions(PA, Renamings) ++ get_questions(PB, Renamings);
get_questions({sharing, {closure, Events}, PA, PB, SPAN}, Renamings) ->
	% Descartar els no factibles (per sincronitzacio)
	% Juntar opcions quan syncronitzacio (contemplant totes les combinacions)
	% la resta fer append
	get_questions(PA, Renamings) ++ get_questions(PB, Renamings);
get_questions({procRenaming, ListRenamings, P, SPAN}, Renamings) ->
	get_questions(P, [ListRenamings | Renamings]);
get_questions({skip, SPAN}, Renamings) ->
	[].

process_answer(P = {prefix, SPAN1, Channels, Event, ProcessPrefixing, SPAN}, P) ->
	ProcessPrefixing;
process_answer(P = {'|~|', PA, PB, SPAN}, P) ->
	PA;
process_answer(P = {agent_call, SPAN, ProcessName, Arguments}, P) ->
	send_message2regprocess(codeserver, {ask_code, ProcessName, Arguments, get_self()}),
	receive
		{code_reply, Code} -> 
			Code
	end;
process_answer({'|||', PA, PB, SPAN}, P) ->
	{'|||', 
		process_answer(PA, P), 
		process_answer(PB, P), 
		SPAN};
process_answer({sharing, {closure, Events}, PA, PB, SPAN}, P) ->
	{sharing, 
		{closure, Events}, 
		process_answer(PA, P), 
		process_answer(PB, P), 
		SPAN};
process_answer({procRenaming, ListRenamings, Proc, SPAN}, P) ->
	{procRenaming, ListRenamings, process_answer(Proc, P), SPAN};
% process_answer({skip, SPAN}, _) ->
% 	{skip, SPAN};
process_answer(P, _) ->
	P.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%   Other functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

format(Format, Data) ->
    lists:flatten(io_lib:format(Format, Data)).

send_message2regprocess(Process,Message) ->
 	ProcessPid = whereis(Process),
 	case ProcessPid of 
 		undefined -> 
 			no_sent;
 		_ -> 
         	case is_process_alive(ProcessPid) of 
         		true -> 
			        ProcessPid!Message;
				false -> 
					no_sent
			end
	end.

get_self() ->
	catch self().

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Main Loops
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
% send_confirmation({event,Event,Channels,Pid,PidPrefixing,_,_}) ->
% 	io:format("Llega evento ~p\n",[Event]),
%     % Channels_ = lists:reverse(Channels),
%     Channels_ = Channels,
% 	SelectedChannels_ = select_channels(Channels_,Event),
% 	% SelectedChannels = lists:reverse(SelectedChannels_),
% 	SelectedChannels = SelectedChannels_,
% 	% io:format("Arriba ~p amb canals ~p\n",[Event,Channels]),
% 	% io:format("CHANNELS: ~p\n",[SelectedChannels]), 
% 	ChannelsString = create_channels_string(SelectedChannels),
% 	EventString = 
% 	    case ChannelsString of
% 	         "" -> 
% 				atom_to_list(Event);
% 			 _ -> 
% 			 	case atom_to_list(Event) of
% 			 	     [$ ,$ ,$ ,$t,$a,$u|_] ->
% 			 	     	atom_to_list(Event);
% 			 	     _ ->  
% 			  		atom_to_list(Event) ++ "." ++ ChannelsString
% 			  	end
% 	    end,
% 	ExecutedEvent = list_to_atom(EventString),
%     send_message2regprocess(printer,{print,ExecutedEvent,get_self()}),
% 	receive
% 	   {printed,ExecutedEvent} -> ok
% 	end,
% 	Pid!{executed,PidPrefixing,get_self(),SelectedChannels},
% 	receive
% 	    _ ->  PidPrefixing!continue
% 	end;
% send_confirmation({choice, Pid, PA, PB}) ->
% 	io:format("Llega choice\n"),
% 	Selected = ask_user([1, 2]),
% 	Pid!{executed, Selected},
% 	receive
% 	    _ ->  Pid!continue
% 	end.

% % subir bifuraciones para saber que hay que que oir a alguie mas
% % cuando se sube un evento se sube los procesos que se estan sincronizando, tanto para mostrarlo como para descontar de pending

% loop_root(First, Active, PendingAsk) 
% 	when length(Active) =:= length(PendingAsk), length(Active) > 0 ->
% 	Answer = ask_user(PendingAsk),
% 	send_confirmation(Answer),
% 	loop_root(First, Active, PendingAsk -- [Answer]);
% loop_root(First, Active, PendingAsk) ->
%     io:format("a la espera root ~p\n",[get_self()]),
% 	receive	
% 		{new_active, NewActive} ->
% 			loop_root(First, [NewActive |Active], PendingAsk);
% 		{finished,_,_} ->
% 			First!ok;
% 		{finished_skip,SPAN,GraphParent,PidSkip,_,IsFinal} ->
% 			print_skip(SPAN,GraphParent,PidSkip,IsFinal),
% 			loop_root(First, Active, PendingAsk);	
% 		{stopped,_} -> 
% 			First!stopped;
% 		E = {event,_,_,_,_,_,_} ->
% 			loop_root(First, Active, [E | PendingAsk]);
% 		C = {choice, _, _, _} ->
% 			loop_root(First, Active, [C | PendingAsk])
% 	end.

% loop(Process,PidParent,GraphParent,PendingSC,Renaming) ->
% 	{NState,NPendingSC,NGraphParent} = 
% 		case Process of
% 		     {finished,_,_} = FinishedState ->
% 		     	{FinishedState,PendingSC,GraphParent};
% 		     {';',PA,PB,SPAN} ->
% 		     	{PA,[{PB,Renaming,SPAN}|PendingSC],GraphParent};
% 		     {skip,SPAN} -> 
% 		     	{{finished_skip,SPAN},PendingSC,GraphParent};
% 	  	     {prefix,SPAN1,Channels,Event,ProcessPrefixing,SPAN2} ->
% 	  	        {NState_,NGraphParent_} =
% 	  	             process({prefix,SPAN1,Channels,Event,
% 			             ProcessPrefixing,SPAN2},
% 			             PidParent,GraphParent,Renaming),
% 	  	        {NState_, PendingSC, NGraphParent_};
% 		     _ ->
% 		        io:format("Create_graph de ~p (~p)\n",[Process,get_self()]),
% 				send_message2regprocess(printer,{create_graph,Process,GraphParent,get_self()}),
% 				receive
% 					{created,NGraphParent_} ->
% 					   Res = process(Process,PidParent,NGraphParent_,Renaming),
% 					   %io:format("res ~p\n",[Res]),
% 					   {Res,
% 					    PendingSC,NGraphParent_}
% 		  		end
% 		end,
%         case NState of
%              {finished_skip,SPANSKIP} ->
%              	% io:format("Envio: ~p\n",[{finished_skip,SPANSKIP,NGraphParent,get_self()}]),
%              	IsFinal =
%              	  case NPendingSC of
%              	       [] -> true;
%              	       _ -> false
%              	  end,
%              	PidParent!{finished_skip,SPANSKIP,NGraphParent,get_self(),get_self(),IsFinal},
%              	receive
%              	   {continue_skip,NNGraphParent} ->
%              	      loop({finished,get_self(),[NNGraphParent]},
%              	            PidParent,NNGraphParent,NPendingSC,Renaming)
%              	end;
%              {finished,Pid,FinishedNodes} -> 
%                   case NPendingSC of
% 	               [{Pending,RenamingOfPending,SPANSC}|TPendingSC] ->
%                            send_message2regprocess(printer,{print,'   tau',get_self()}),
%                            send_message2regprocess(printer,{create_graph,{';',FinishedNodes,SPANSC},-1,get_self()}),
%                            receive
% 			     			{printed,'   tau'} -> 
% 			   					ok
% 			   			   end,
% 						   receive
% 						      {created,NodeSC} -> 
% 						      	% io:format("CONTINUA in ~p\n", [self()]),
% 							   loop(Pending,PidParent,NodeSC,TPendingSC,RenamingOfPending)
% 						   end;
%                     _ ->
%                  	   PidParent!{finished,Pid,FinishedNodes}
%                  end;
%              {stopped,Pid} -> 
%              	%io:format("Entra\n"),
%              	PidParent!{stopped,Pid};
%              {renamed,NProcess,NRenaming} -> 
%              	loop(NProcess,PidParent,NGraphParent,NPendingSC,NRenaming);
%              NProcess ->
%              	%io:format("Loop (~p) from ~p to ~p \n",[get_self(),Process,NProcess]),
%              	loop(NProcess,PidParent,NGraphParent,NPendingSC,Renaming)
%         end.
        
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Process Function
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% process({prefix,_,Channels,Event,Process,_}=Prefixing,PidParent,GraphParent,Renaming) -> 
% 	ExecutedEvent = rename_event(Event,Renaming),
% 	% io:format("\tProcess: ~p\n", [Channels]),
% 	% io:format("Prefixing in ~p: ~p\n", [self(), {Channels,Event}]),
% 	prefixing_loop(PidParent,Prefixing,Process,GraphParent,
% 	              {event,ExecutedEvent,Channels,get_self(),get_self(),Prefixing,GraphParent},
% 	              Channels);
% process({'|~|',PA,PB,_}, PidParent ,_,_) ->
% 	process_choice(PA,PB,true, PidParent);
% process({'[]',PA,PB,_},PidParent,GraphParent,Renaming) ->
%     {PA_,PB_} = random_branches(PA,PB),
% 	process_external_choice([PA_,PB_],PidParent,GraphParent,Renaming);
% 	% process_external_choice(PA_,PB_,PidParent,GraphParent,Renaming);
% process({'ifte',Condition,PA,PB,_,_,_},_,_,_) ->
% 	Event = list_to_atom("   tau -> Condition Choice value "++atom_to_list(Condition)),
% 	send_message2regprocess(printer,{print,Event,get_self()}),
% 	receive
% 		{printed,Event} -> ok
% 	end,
% 	case Condition of
% 	     true -> PA;
% 	     false -> PB
% 	end;
% process(AC = {agent_call,_,ProcessName,Arguments}, PidParent, _, _) ->
%    	Event = 
%    		list_to_atom("   tau -> Call to process " ++ atom_to_list(ProcessName)
% 		++ printer:string_arguments(Arguments)),
% 	Msg = {event,Event,[],get_self(),get_self(),none,none},
% 	process_call_loop(PidParent, AC, Msg);
% process({sharing,{closure,Events},PA,PB,_},PidParent,GraphParent,Renaming) ->
%     {PA_,PB_} = 
%     	random_branches(PA,PB),
% 	process_parallelism(PA_,PB_,Events,PidParent,GraphParent,Renaming);
% process({'|||',PA,PB,_},PidParent,GraphParent,Renaming) ->
%         {PA_,PB_} = random_branches(PA,PB),
% 	process_parallelism(PA_,PB_,[],PidParent,GraphParent,Renaming);
% process({procRenaming,ListRenamings,P,_},_,_,Renaming) ->
% 	{renamed,P,[ListRenamings|Renaming]};
% process({'\\',P,{closure,Events},_},_,_,Renaming) ->
% 	{renamed,P,[[{rename,Event,'   tau -> Hidding'}] || Event <- Events] ++ Renaming};
% process({stop,_},_,_,_) ->
% 	send_message2regprocess(printer,{print,'   tau -> STOP',get_self()}),
% 	receive
% 		{printed,'   tau -> STOP'} -> {stopped,get_self()}
% 	end.


% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Process Call
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%	
	
% process_call_loop(Pid, AC = {agent_call,_,ProcessName,Arguments}, Msg) ->
% 	% io:format("\nEnvia a ~p el missatge ~p\n",[Pid,Message]),
% 	Pid!Msg,
% 	receive 
% 		{executed,_,_,_} ->
% 			% send_message2regprocess(printer, {print, Event, get_self()}),
% 			io:format("Seguix\n"),
% 			send_message2regprocess(codeserver, {ask_code, ProcessName, Arguments, get_self()}),
% 			receive
% 				{code_reply,Code} -> 
% 					ok
% 			end,
% 			Pid!{sync_info,[none]},
% 	        receive
% 	           continue -> 
% 	           		Code 
% 	        end
% 	end.


% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Prefixing 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
% prefixing_loop(Pid,Prefixing,Process,GraphParent,Message,Channels) ->
% 	% io:format("\nEnvia a ~p el missatge ~p\n",[Pid,Message]),
% 	Pid!Message,
% 	receive 
% 		{executed,_,Pid,SelectedChannels} ->
% 				% io:format("\tEXE_Chan: ~p\n\tEXE_SCHan: ~p\n",[Channels,SelectedChannels]),
% 				{event,ExecutedEvent,_,_,_,_,_} = Message,
% 		        Dict = createDict(Channels,SelectedChannels,ExecutedEvent),
% 		        NPrefixing = csp_parsing:replace_parameters(Prefixing,Dict),
% 		        % io:format("Dict: ~p\nAntes: ~p\nDespues: ~p\n",[Dict,Prefixing,NPrefixing]),
% 		        % io:format("ExecutedEvent: ~p\n",[ExecutedEvent]),
% 		        % io:format("SelectedChannels: ~p\n",[SelectedChannels]),
% 		        send_message2regprocess(printer,{create_graph,{renamed_event,ExecutedEvent,NPrefixing},GraphParent,get_self()}),
% 				{prefix,_,_,_,NProcess,_} = NPrefixing,
% 				receive
% 			           {created,NParent} -> 
% 					       Pid!{sync_info,[NParent-1]},
% 					       receive
% 					           continue -> ok 
% 					       end,
% 					       {NProcess,NParent}
% 				end;
%        	rejected ->
% 		%timer:sleep(50),
% 			% io:format("\nREJECTED ~p el missatge ~p\n",[Pid,Message]),
% 			prefixing_loop(Pid,Prefixing,Process,GraphParent,Message,Channels);
% 		rejected_all ->
% 		%timer:sleep(50),
% 			% io:format("\nREJECTED_ALL ~p el missatge ~p\n",[Pid,Message]),
% 			{{stopped,get_self()},GraphParent}
% 	end.
	
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Internal Choice 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% %Controlar que no quede una unica crida a esta funció	
% process_choice(PA, PB, PrintTau, Pid) ->
% 	Pid!{choice, get_self(), PA, PB},
% 	receive 
% 		{executed, Selected} -> 
% 			% rand:seed(exs64),
% 			% Selected = rand:uniform(2),
% 			io:format("Selected ~p\n", [Selected]),
% 			case PrintTau of
% 			     true ->
% 				Event = list_to_atom("   tau -> Internal Choice. Branch " ++ integer_to_list(Selected)),
% 				send_message2regprocess(printer,{print,Event,get_self()}),
% 				receive
% 					{printed,Event} -> ok
% 				end;
% 			     false ->
% 			      	ok
% 			end, 
% 			NProcess = 
% 				case Selected of
% 				     1 -> PA;
% 				     2 -> PB
% 				end,
% 		   Pid!{sync_info,[none]},
% 	       receive
% 	           continue -> ok 
% 	       end,
% 	       NProcess
% 	end.
	
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Parallelisms
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
% process_parallelism(PA,PB,Events,PidParent,GraphParent,Renaming) ->
% 	PidA = spawn(csp_process_interactive,loop,[PA,get_self(),GraphParent,[],[]]),
% 	PidB = spawn(csp_process_interactive,loop,[PB,get_self(),GraphParent,[],[]]),
% 	% io:format("Parallelisme fill de ~p: ~p\n",[get_self(),{PidA,PidB}]),
% 	parallelism_loop(PidA,PidB,Events,PidParent,[],Renaming,{{},{}}, none).
	
% parallelism_loop(PidA,PidB,SyncEvents,PidParent,Finished,Renaming,TemporalGraphs, OtherBranchEvent) ->
% 	% io:format("LOOP Parallelisme fill de ~p: ~p\n",[get_self(),{PidA,PidB}]),
% 	case length([Fin || Fin = {_,NodesFinished} <- Finished, NodesFinished =/=[]]) of
% 	     2 -> 
% 	       % io:format("FIN Parallelisme fill de ~p: ~p\n",[get_self(),{PidA,PidB}]),
% 	       {finished,get_self(),lists:append([NodesFinished || 
% 		                              {_,NodesFinished} <- Finished])};
% %	       send_message2regprocess(printer,{print,tick_SP,get_self()}),
% %	       receive
% %		      {printed,tick_SP} -> 
% %		         {finished,get_self(),
% %		                   lists:append([NodesFinished || 
% %		                                 {_,NodesFinished} <- Finished])}
% %	       end;
% 	     _ ->
% 	     	case length(Finished) of
% 	     		  2 -> 
% 	     		  	{stopped,get_self()};
% 	     		  _ -> 
% 	     		  	% io:format("A la escolta SP ~p\n",[get_self()]),
% 					receive
% 					   {finished_skip,SPANSKIP,GraphParentSkip,PidSkip,PidAorB,true} -> 
% 					   		Send = 
% 						      case length([Fin || Fin = {_,NodesFinished} <- Finished, 
% 						      						NodesFinished =/=[]]) of
% 							   1 -> 
% 							       PidParent!{finished_skip,SPANSKIP,GraphParentSkip,
% 							                  PidSkip,get_self(),true};
% 							   _ -> 
% 							       PidParent!{finished_skip,SPANSKIP,GraphParentSkip,
% 							                  PidSkip,get_self(),false} 
% 						      end,
% 					      receive
% 					        {finished,PidAorB,NodesFinished} ->
% 					           parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                            [{PidAorB,NodesFinished}|Finished],
% 					                            Renaming,TemporalGraphs, OtherBranchEvent);
% 					        Other ->
% 					        	self()!Other,
% 					        	parallelism_loop(PidA,PidB,SyncEvents,PidParent,Finished,Renaming,TemporalGraphs, OtherBranchEvent)
% 					      end;
% 					   {finished_skip,_,_,_,_,false} = Message ->
% 					      PidParent!Message,
% 					      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                        Finished,Renaming,TemporalGraphs, OtherBranchEvent);
% 					   {finished,PidA,NodesFinished} ->
% 					      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                        [{PidA,NodesFinished}|Finished]
% 					                        ,Renaming,TemporalGraphs, OtherBranchEvent);
% 					   {finished,PidB,NodesFinished} ->
% 					      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                       [{PidB,NodesFinished}|Finished],
% 					                       Renaming,TemporalGraphs, OtherBranchEvent);
% 					   {stopped,PidA} ->
% 			 		      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 			                       [{PidA,[]}|Finished],
% 			                       Renaming,TemporalGraphs, OtherBranchEvent);
% 			 		   {stopped,PidB} ->
% 			 		      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 			                       [{PidB,[]}|Finished],
% 			                       Renaming,TemporalGraphs, OtherBranchEvent);
% 					   % {event,_,_,PidA,_,_,_} = Message ->
% 					   {events_list,PidA,_} = Message ->
% 					       parallelism_event(Message,PidA,PidB,SyncEvents,
% 					   	                  PidParent,Finished,Renaming,TemporalGraphs);
% 					   % {event,_,_,PidB,_,_,_} = Message ->
% 					   {events_list,PidB,_} = Message ->
% 					   		parallelism_event(Message,PidA,PidB,SyncEvents,
% 					   	                  PidParent,Finished,Renaming,TemporalGraphs)        
% 					end
% 	     	end 
% 	end.

% {event,Event,Channels,Pid,[[{PidPrefixing,Prefixing,GraphParent}]]}


% parallelism_event({event,Event,Channels,Pid,PidPrefixing,Prefixing,GraphParent},PidA,PidB,
%                   SyncEvents,PidParent,Finished,Renaming,TemporalGraphs) ->
% 	% io:format("\tparallelism: ~p\n", [Channels]),
% 	% io:format("Event Parallelisme ~p: ~p\n",[{PidA,PidB}, Event]),
% 	ExecutedEvent = rename_event(Event,Renaming),
% 	Pids = 
% 		case Pid =:= PidA of
% 		    true ->
% 		    	{PidA,PidB};
% 		    false ->
% 		    	{PidB,PidA}
% 		end, 
% 	NTemporalGraphs =  
% 		process_event(Event,ExecutedEvent,Pids,PidPrefixing,   
% 	                 Channels,SyncEvents,PidParent,
% 	                 Prefixing,GraphParent,
% 	                 TemporalGraphs,PidA,PidB,
% 	                 Finished),      
% 	parallelism_loop(PidA,PidB,SyncEvents,PidParent,
%                  Finished,Renaming,NTemporalGraphs).

% process_event(Event,ExecutedEvent,{PidA,PidB},PidPrefixingA,ChannelsA,
%               SyncEvents,PidParent,PrefixingA,GraphParentA,
%               TemporalGraphs,PidAOri,PidBOri,Finished) ->
%        % io:format("SP ~p processa event ~p enviat per ~p\n",
%        %           [get_self(),Event,PidA]),
% 	case lists:member(Event,SyncEvents) of
% 	     true ->
% 	       	NTemporalGraphs_ = remove_temporal_graph(PidA,TemporalGraphs),
%         	NTemporalGraphs = create_temporal_graph(PidA,NTemporalGraphs_,PrefixingA,
%                                                 GraphParentA,PidAOri,PidBOri),
% 	        case length(Finished) of
% 	             1 -> 
% 	             	PidA!rejected_all,
% 			  		NTemporalGraphs;
% 	             _ -> 
% 	              	receive
% 	              	    {event,Event,ChannelsB,PidB,PidPrefixingB,_,_} -> 
% 	              	    	% io:format("\t\tChannelsA: ~p\n\t\tChannelsB: ~p\n\t\tCreate: ~p\n",[ChannelsA,ChannelsB,create_channels(ChannelsA,ChannelsB,[])]),     
% 	              	        case create_channels(ChannelsA,ChannelsB,[]) of
% 	              	             no_compatible ->
% 	              	                PidA!rejected,
% 							        PidB!rejected,
% 							        NTemporalGraphs;
% 				     			SelectedChannels ->   	              	    		  
% 									process_both_branches(ExecutedEvent,
% 									        PidA,PidPrefixingA,
% 									        PidB,PidPrefixingB,
% 									        SelectedChannels,
% 						                    PidParent,NTemporalGraphs)
% 	              	        end
% 	              	after 
% 	              	    0 -> 
% 	              	    	receive
% 	              	    	   {event,Event,ChannelsB,PidB,PidPrefixingB,_,_} ->
% 	              	    	   	% io:format("\t\tChannelsA: ~p\n\t\tChannelsB: ~p\n\t\tCreate: ~p\n",[ChannelsA,ChannelsB,create_channels(ChannelsA,ChannelsB,[])]),     
% 		              	    	case create_channels(ChannelsA,ChannelsB,[]) of
% 		              	            no_compatible ->
% 		              	                PidA!rejected,
% 					        			PidB!rejected,
% 					        			NTemporalGraphs;
% 					     			SelectedChannels ->   	              	    	  
% 										process_both_branches(ExecutedEvent,
% 										        PidA,PidPrefixingA,
% 										        PidB,PidPrefixingB,
% 										        SelectedChannels,
% 							                    PidParent,NTemporalGraphs)
% 		              	        end;
% 			                   Message ->
% 			                        PidA!rejected,
% 			                   		get_self()!Message,
% 			                   		NTemporalGraphs		                   
% 	              	    	end
% 	              	end
% 	        end;
%    	     false -> 
%    	         PidParent!{event,ExecutedEvent,ChannelsA,get_self(),
%    	                    PidPrefixingA,PrefixingA,GraphParentA},
%                  receive
%                    {executed,PidPrefixingA,PidParent,SelectedChannels} -> 
%                       NTemporalGraphs = remove_temporal_graph(PidA,TemporalGraphs),
%                       PidA!{executed,PidPrefixingA,get_self(),SelectedChannels},
%                       receive
%                          {sync_info,_} = Message ->
%                             PidParent ! Message
%                       end,
%                       NTemporalGraphs
%                    % rejected ->
%                    %    PidA!rejected,
%                    %    TemporalGraphs
%                   end
% 	end.

% process_both_branches(ExecutedEvent,PidA,PidPrefixingA,PidB,PidPrefixingB,
%                       SelectedChannels,PidParent,NTemporalGraphs) ->	
% 	PidParent!{event,ExecutedEvent,SelectedChannels,get_self(),get_self(),{},-1},
% 	receive
% 	   {executed,_,PidParent,FinallySelectedChannels} ->
% 	       NNTemporalGraphs_ = remove_temporal_graph(PidA,NTemporalGraphs),
% 	       NNTemporalGraphs = remove_temporal_graph(PidB,NNTemporalGraphs_),
% 	       PidA!{executed,PidPrefixingA,get_self(),FinallySelectedChannels},
% 	       PidB!{executed,PidPrefixingB,get_self(),FinallySelectedChannels},
% 	       receive
% 	           {sync_info,NodesA} ->
% 	              ok
% 	       end,
% 	       receive
% 	           {sync_info,NodesB} ->
% 	              ok
% 	       end,
% 	       PidPrefixingA!continue,
% 	       PidPrefixingB!continue,
% 	       [print_sync(NodeA,NodeB) || NodeA <- NodesA, 
% 		                           NodeB <- NodesB],
% 	       PidParent!{sync_info,NodesA ++ NodesB},
% 	       receive
% 	           continue -> ok
% 	       end,
% 	       NNTemporalGraphs
% 	   % rejected -> 
% 	   %   PidA!rejected,
% 	   %   PidB!rejected,
% 	   %   NTemporalGraphs;
% 	   % rejected_all -> 
% 	   %   PidA!rejected_all,
% 	   %   PidB!rejected_all,
% 	   %   NTemporalGraphs
% 	end.	

% print_sync(NodeA,NodeB) ->
% 	send_message2regprocess(printer,{print_sync,NodeA,NodeB,get_self()}),
% 	receive
%            {printed_sync,NodeA,NodeB} ->
%    	       ok
% 	end.
	
	
% create_channels([],[],FinalChannels) -> 
% 	lists:reverse(FinalChannels);
% create_channels([{out,Channel}|CA],[{in,_}|CB],FinalChannels) ->
% 	create_channels(CA,CB,[{out,Channel}|FinalChannels]);
% create_channels([{out,Channel}|CA],[{'inGuard',_,Channels}|CB],FinalChannels) ->
% 	case lists:member(Channel,Channels) of
% 	     true -> create_channels(CA,CB,[{out,Channel}|FinalChannels]);
% 	     false -> no_compatible
% 	end;
% create_channels([{out,ChannelA}|CA],[{out,ChannelB}|CB],FinalChannels) ->
% 	case ChannelA=:=ChannelB of
% 	     true -> create_channels(CA,CB,[{out,ChannelA}|FinalChannels]);
% 	     false -> no_compatible
% 	end;
% create_channels([{in,_}|_],[{in,_}|_],_) ->
% 	no_compatible;
% create_channels([{in,_}|CA],[{'inGuard',Var,Channels}|CB],FinalChannels) ->
% 	create_channels(CA,CB,[{'inGuard',Var,Channels}|FinalChannels]);
% create_channels([{'inGuard',Var,ChannelsA}|CA],[{'inGuard',_,ChannelsB}|CB],FinalChannels) ->
% 	Intersection = 
% 	   sets:tolist(sets:intersection(sets:from_list(ChannelsA),sets:from_list(ChannelsB))),
% 	case Intersection of
% 	     [] -> no_compatible;
% 	     _ -> 
% 	       create_channels(CA,CB,[{'inGuard',Var,Intersection}|FinalChannels])
% 	end;
% create_channels(ChannelsA,ChannelsB,FinalChannels) ->
% 	create_channels(ChannelsB,ChannelsA,FinalChannels).

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   External Choices 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	
% process_external_choice(PList0,PidParent,GraphParent,Renaming) ->
% 	PList = 
% 	% From: http://stackoverflow.com/a/8820501/4162959
% 		[X || {_,X} <- lists:sort(
% 			[ {rand:uniform(), P} || P <- PList0])],
% 	PidList = 
% 		[spawn(csp_process_interactive,loop,[P,get_self(),GraphParent,[],[]]) 
% 	 	 || P <- PList],
% 	external_choice_loop(PidList,PidParent,Renaming).
	

% external_choice_loop(PidList,PidParent,Renaming) ->
% 	% io:format("External choice ~p -> ~p\n", [self(), PidList]),
% 	receive
% 	   {finished_skip,SPANSKIP,GraphParentSkip,PidSkip,Pid,true} ->
% 	   		case lists:member(Pid, PidList) of 
% 	   			true -> 
% 					PidParent!
% 						{finished_skip,
% 							SPANSKIP,GraphParentSkip,
% 							PidSkip,get_self(),true},
% 					receive
% 						{finished,Pid,NodesFinished} -> 
% 						   	case PidList of 
% 						   	 	[Pid] ->
% 						   	 		{finished,get_self(),NodesFinished};
% 						   	 	_ ->
% 						   	 		finish_external_choice(NodesFinished)
% 						   	 end
% 					end;
% 				false -> 
% 					external_choice_loop(PidList,PidParent,Renaming)
% 			end;
% 	   {finished_skip,SPANSKIP,GraphParentSkip,PidSkip,Pid,false} ->
% 		   	case lists:member(Pid,PidList) of 
% 		   		true ->
% 				    PidParent!
% 				    	{finished_skip,
% 				    		SPANSKIP,GraphParentSkip,
% 				    		PidSkip,get_self(),false},
% 				    external_choice_loop(PidList,PidParent,Renaming);
% 				false ->
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end;
% 	   {finished,Pid,NodesFinished} ->
% 	   		case lists:member(Pid,PidList) of
% 	   			true ->
% 					case PidList of 
% 						[Pid] ->
% 							{finished,get_self(),NodesFinished};
% 						_ ->
% 							finish_external_choice(NodesFinished)
% 					end; 
% 				false -> 
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end;
% 	   {stopped,Pid} ->
% 	   		case lists:member(Pid,PidList) of
% 	   			true ->
% 					NPidList = PidList -- [Pid], 
% 					case NPidList of 
% 						[] -> 
% 							{stopped,get_self()};
% 						_ -> 
% 							external_choice_loop(NPidList,PidParent,Renaming) 
% 					end;
% 				false -> 
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end;
% 	   {event,Event,Channels,Pid,PidPrefixing,Prefixing,GraphParent} ->
% 	   		% io:format("External choice ~p -> received event ~p\n", [self(), {Event,Pid}]),
% 		   	case lists:member(Pid,PidList) of
% 	   			true ->	
% 					ExecutedEvent = rename_event(Event,Renaming),
% 					% io:format("External choice ~p -> envia a parent ~p\n", [self(), {Event,PidParent}]),
% 					PidParent!
% 						{event,
% 							ExecutedEvent,Channels,get_self(),
% 							PidPrefixing,Prefixing,GraphParent},
% 					process_event_ec(
% 						Renaming,PidPrefixing,PidParent,Pid,PidList);
% 				false ->
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end
% 	end.	
       
% process_event_ec(Renaming,PidPrefixing,PidParent,Pid,PidList) ->
% 	% io:format("Receiving event ~p\n", [self()]),
% 	receive
% 		{executed,PidPrefixing,PidParent,SelectedChannels} -> 
% 			Pid!{executed,PidPrefixing,get_self(),SelectedChannels},
% 			receive
% 			 	{sync_info,_} = Message ->
% 			    	PidParent ! Message
% 			end,
% 			% io:format("One process ~p -> ~p\n", [self(), Pid]),
% 	      	external_choice_loop([Pid],PidParent,Renaming);
% 		rejected -> 
% 			Pid!rejected,
% 			external_choice_loop(PidList,PidParent,Renaming);
% 		rejected_all -> 
% 			Pid!rejected_all,
% 			external_choice_loop(PidList,PidParent,Renaming)
% 	end.

% finish_external_choice(NodesFinished) ->
% 	send_message2regprocess(printer,{print,tick_EC,get_self()}),
% 	receive
% 	  {printed,tick_EC} -> 
% 	     {finished,get_self(),NodesFinished}
% 	end.

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Other Functions
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	
% rename_event(Event,[List|TailRenaming]) ->
% 	rand:seed(exs64),
% 	ShuffledList = 
% 		[X || {_,X} <- lists:sort([ {rand:uniform(), N} || N <- List])],
% 	rename_event(rename_event_list(Event,ShuffledList),TailRenaming);
% % rename_event(Event,[_|TailRenaming]) ->
% % 	rename_event(Event,TailRenaming);
% rename_event(Event,[]) -> 
% 	Event.

% rename_event_list(Event,[{rename,Event,Renamed}|_]) ->
% 	Renamed;
% rename_event_list(Event,[_|Tail]) ->
% 	rename_event_list(Event,Tail);
% rename_event_list(Event,[]) ->
% 	Event.

% %vore que no quede una unica cria a aquesta funció
% print_skip(SPAN,GraphParent,PidSkip,IsFinal) ->	
% 	send_message2regprocess(printer,{create_graph,{skip,SPAN},GraphParent,get_self()}),
% 	NGraphParent = 
% 		receive
% 		   {created,NGraphParent_} -> NGraphParent_
% 		end,
% 	case IsFinal of
% 	     true -> send_message2regprocess(printer,{print,'   tick',get_self()});
% 	     false -> send_message2regprocess(printer,{print,'   tau',get_self()})
% 	end,
% 	receive
% 	   {printed,'   tick'} -> 
% 		  ok;
%            {printed,'   tau'} -> 
% 		  ok
% 	end,
% 	PidSkip!{continue_skip,NGraphParent}.
	
% remove_temporal_graph(Pid,TemporalGraphs) ->	
%         case TemporalGraphs of
%              {{Pid,IdAno},Other} ->
% 				send_message2regprocess(printer,{remove_graph_no_ided,IdAno,get_self()}),
% 				receive
% 				    {removed,IdAno} ->
% 				    	{{},Other}
% 				end;
%              {Other,{Pid,IdAno}} ->
% 				send_message2regprocess(printer,{remove_graph_no_ided,IdAno,get_self()}),
% 				receive
% 				    {removed,IdAno} ->
% 				    	{Other,{}}
% 				end;
%              _ -> 
%              	TemporalGraphs
%         end.
        
% create_temporal_graph(Pid,{TGraphA,TGraphB},Prefixing,GraphParent,PidA,PidB) ->	 
%     case Prefixing of 
%          {} ->
%             {TGraphA,TGraphB};
%          _ ->
% 			send_message2regprocess(printer,{create_graph_no_ided,Prefixing,GraphParent,get_self()}),
% 			receive
% 			    {created_no_id,IdAno} ->
% 			    	ok
% 			end,
% 			case Pid of
% 			     PidA ->
% 			        {{Pid,IdAno},TGraphB};
% 			     PidB ->
% 			     	{TGraphA,{Pid,IdAno}}
% 			end
% 	end.	
	
% random_branches(PA,PB) ->
% 	rand:seed(exs64),
% 	Selected = rand:uniform(2),
% 	case Selected of
% 		1 -> {PA,PB};
% 		2 -> {PB,PA}
% 	end. 

% select_channels([{out,Channel}|Tail],Event) ->
% 	% io:format("Event: ~p\nChannel: ~p\n",[Event,Channel]),	
% 	[Channel|select_channels(Tail,Event)];
% select_channels([{'inGuard',_,ChannelsList}|Tail],Event) ->
%         rand:seed(exs64),
%         Selected = rand:uniform(length(ChannelsList)),
% 	[lists:nth(Selected,ChannelsList)|select_channels(Tail,Event)];
% select_channels([{in,_}|Tail],Event) ->
% 	send_message2regprocess(codeserver,{ask_channel,Event,get_self()}),
% 	% io:format("Event: ~p\n",[Event]),
% 	% ChannelsR = 
% 	Channels = 
% 		receive
% 			{channel_reply,Channels_} -> Channels_
% 		end,
% 	% Channels = lists:reverse(ChannelsR),
% 	% io:format("Channels_: ~p\n",[Channels_]),
% 	NTail = 
% 		try 
% 			lists:sublist(Tail,length(Channels),length(Tail))
% 		catch
% 			_:_ -> []
% 		end,
% 	% io:format("Channels: ~p\n",[Channels]),
% 	Channels ++ select_channels(NTail,Event);
% select_channels(Other = [_|_],_) ->
% 	% io:format("Other type of channel: ~p\n",[Other]),
% 	[];
% select_channels([],_) ->
% 	[].
	
% create_channels_string([]) ->
% 	"";
% create_channels_string([Channel]) when is_integer(Channel) ->
% 	integer_to_list(Channel);
% create_channels_string([Channel]) when is_atom(Channel) ->
% 	atom_to_list(Channel);
% create_channels_string([Channel|Tail]) when is_integer(Channel) ->
% 	integer_to_list(Channel)++"."++create_channels_string(Tail);
% create_channels_string([Channel|Tail]) when is_atom(Channel) ->
% 	atom_to_list(Channel)++"."++create_channels_string(Tail).
	
% createDict([{'inGuard',Var,_}|TC],[Selected|TS],EE) when is_list(Var) ->
% 	[{list_to_atom(Var),Selected}|createDict(TC,TS,EE)];
% createDict([{'inGuard',Var,_}|TC],[Selected|TS],EE) when is_atom(Var) ->
% 	[{Var,Selected}|createDict(TC,TS,EE)];
% createDict([{in,Var}|TC],[Selected|TS],EE) when is_list(Var) ->
% 	[{list_to_atom(Var),Selected}|createDict(TC,TS,EE)];
% createDict([{in,Var}|TC],[Selected|TS],EE) when is_atom(Var) ->
% 	[{Var,Selected}|createDict(TC,TS,EE)];
% createDict([{in,_}|_],_,EE) ->
% 	throw(lists:flatten(io_lib:format("Detected an in-channel without defined options while executing event ~p", [EE])));
% createDict([{out,_}|TC],[_|TS],EE) ->
% 	createDict(TC,TS,EE);
% createDict([],[],_) ->
% 	[].


% Ideas: 
% - Los paralelismos suben listas de eventos (uno por cada rama). Puede que alguna rama este muerta ya. Subir entonces esa info de alguan manera
% - Cuando a un paralelismo le llegan una lista de paralelismos, entonces tiene que crear todas la combinaciones posibles por ejemplo ( a |a| (a ||| a) ) puede sincronizar de dos maneras dierentes. Todas estas opciones deben de subir para que puedan preguntarse
% - En definitiva lo que se sube es una lista del tipo [{evento, [PROCESOS_IMPLICADOS]}]. Un evento puede repetirse en esa lista con lo cual se haran combinaciones diferentes. 
% - Cuando una de las combinaciones sea seleccionado por el usuario, baja 
% - Lo del loop principal habrá que repensarlo ya que los pending no tiene mucho sentido (siempre recibe todo lo ejecutable a traves de listas de eventos)

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Main interface
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%

% start(FirstProcess, PidInteraction) -> 
% 	io:format("Entrem\n"),
% 	Root = 
% 		spawn(csp_process_interactive,loop_root,[get_self(), [], []]),
% 	FirstExp = 
% 		{agent_call,{src_span,0,0,0,0,0,0},FirstProcess,[]},
% 	FirstPid = 
% 		spawn(csp_process_interactive,loop,[FirstExp,Root,-1,[],[]]),
% 	Root!{new_active, {FirstPid, FirstExp}},
% 	receive
% 		ok -> 	
% 			ok;
% 		stopped -> 	
% 			ok 
% 	end,
% 	exit(Root, kill),
% 	send_message2regprocess(printer,{info_graph,get_self()}),
% 	InfoGraph = 
% 		receive 
% 			{info_graph, InfoGraph_} ->
% 				InfoGraph_
% 		after 
% 			1000 -> 
% 				{{{0,0,0,now()},"",""},{[],[]}}
% 		end,
% 	send_message2regprocess(printer,stop),
% 	InfoGraph.

% print_message(Msg,NoOutput) ->
% 	case NoOutput of 
% 		false ->
% 			io:format(Msg);
% 		true ->
% 			ok
% 	end.

% ask_user(List) ->
% 	rand:seed(exs64),
% 	Selected = rand:uniform(length(List)),
% 	lists:nth(Selected, List).

	
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Main Loops
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
% send_confirmation({event,Event,Channels,Pid,PidPrefixing,_,_}) ->
% 	io:format("Llega evento ~p\n",[Event]),
%     % Channels_ = lists:reverse(Channels),
%     Channels_ = Channels,
% 	SelectedChannels_ = select_channels(Channels_,Event),
% 	% SelectedChannels = lists:reverse(SelectedChannels_),
% 	SelectedChannels = SelectedChannels_,
% 	% io:format("Arriba ~p amb canals ~p\n",[Event,Channels]),
% 	% io:format("CHANNELS: ~p\n",[SelectedChannels]), 
% 	ChannelsString = create_channels_string(SelectedChannels),
% 	EventString = 
% 	    case ChannelsString of
% 	         "" -> 
% 				atom_to_list(Event);
% 			 _ -> 
% 			 	case atom_to_list(Event) of
% 			 	     [$ ,$ ,$ ,$t,$a,$u|_] ->
% 			 	     	atom_to_list(Event);
% 			 	     _ ->  
% 			  		atom_to_list(Event) ++ "." ++ ChannelsString
% 			  	end
% 	    end,
% 	ExecutedEvent = list_to_atom(EventString),
%     send_message2regprocess(printer,{print,ExecutedEvent,get_self()}),
% 	receive
% 	   {printed,ExecutedEvent} -> ok
% 	end,
% 	Pid!{executed,PidPrefixing,get_self(),SelectedChannels},
% 	receive
% 	    _ ->  PidPrefixing!continue
% 	end;
% send_confirmation({choice, Pid, PA, PB}) ->
% 	io:format("Llega choice\n"),
% 	Selected = ask_user([1, 2]),
% 	Pid!{executed, Selected},
% 	receive
% 	    _ ->  Pid!continue
% 	end.

% % subir bifuraciones para saber que hay que que oir a alguie mas
% % cuando se sube un evento se sube los procesos que se estan sincronizando, tanto para mostrarlo como para descontar de pending

% loop_root(First, Active, PendingAsk) 
% 	when length(Active) =:= length(PendingAsk), length(Active) > 0 ->
% 	Answer = ask_user(PendingAsk),
% 	send_confirmation(Answer),
% 	loop_root(First, Active, PendingAsk -- [Answer]);
% loop_root(First, Active, PendingAsk) ->
%     io:format("a la espera root ~p\n",[get_self()]),
% 	receive	
% 		{new_active, NewActive} ->
% 			loop_root(First, [NewActive |Active], PendingAsk);
% 		{finished,_,_} ->
% 			First!ok;
% 		{finished_skip,SPAN,GraphParent,PidSkip,_,IsFinal} ->
% 			print_skip(SPAN,GraphParent,PidSkip,IsFinal),
% 			loop_root(First, Active, PendingAsk);	
% 		{stopped,_} -> 
% 			First!stopped;
% 		E = {event,_,_,_,_,_,_} ->
% 			loop_root(First, Active, [E | PendingAsk]);
% 		C = {choice, _, _, _} ->
% 			loop_root(First, Active, [C | PendingAsk])
% 	end.

% loop(Process,PidParent,GraphParent,PendingSC,Renaming) ->
% 	{NState,NPendingSC,NGraphParent} = 
% 		case Process of
% 		     {finished,_,_} = FinishedState ->
% 		     	{FinishedState,PendingSC,GraphParent};
% 		     {';',PA,PB,SPAN} ->
% 		     	{PA,[{PB,Renaming,SPAN}|PendingSC],GraphParent};
% 		     {skip,SPAN} -> 
% 		     	{{finished_skip,SPAN},PendingSC,GraphParent};
% 	  	     {prefix,SPAN1,Channels,Event,ProcessPrefixing,SPAN2} ->
% 	  	        {NState_,NGraphParent_} =
% 	  	             process({prefix,SPAN1,Channels,Event,
% 			             ProcessPrefixing,SPAN2},
% 			             PidParent,GraphParent,Renaming),
% 	  	        {NState_, PendingSC, NGraphParent_};
% 		     _ ->
% 		        io:format("Create_graph de ~p (~p)\n",[Process,get_self()]),
% 				send_message2regprocess(printer,{create_graph,Process,GraphParent,get_self()}),
% 				receive
% 					{created,NGraphParent_} ->
% 					   Res = process(Process,PidParent,NGraphParent_,Renaming),
% 					   %io:format("res ~p\n",[Res]),
% 					   {Res,
% 					    PendingSC,NGraphParent_}
% 		  		end
% 		end,
%         case NState of
%              {finished_skip,SPANSKIP} ->
%              	% io:format("Envio: ~p\n",[{finished_skip,SPANSKIP,NGraphParent,get_self()}]),
%              	IsFinal =
%              	  case NPendingSC of
%              	       [] -> true;
%              	       _ -> false
%              	  end,
%              	PidParent!{finished_skip,SPANSKIP,NGraphParent,get_self(),get_self(),IsFinal},
%              	receive
%              	   {continue_skip,NNGraphParent} ->
%              	      loop({finished,get_self(),[NNGraphParent]},
%              	            PidParent,NNGraphParent,NPendingSC,Renaming)
%              	end;
%              {finished,Pid,FinishedNodes} -> 
%                   case NPendingSC of
% 	               [{Pending,RenamingOfPending,SPANSC}|TPendingSC] ->
%                            send_message2regprocess(printer,{print,'   tau',get_self()}),
%                            send_message2regprocess(printer,{create_graph,{';',FinishedNodes,SPANSC},-1,get_self()}),
%                            receive
% 			     			{printed,'   tau'} -> 
% 			   					ok
% 			   			   end,
% 						   receive
% 						      {created,NodeSC} -> 
% 						      	% io:format("CONTINUA in ~p\n", [self()]),
% 							   loop(Pending,PidParent,NodeSC,TPendingSC,RenamingOfPending)
% 						   end;
%                     _ ->
%                  	   PidParent!{finished,Pid,FinishedNodes}
%                  end;
%              {stopped,Pid} -> 
%              	%io:format("Entra\n"),
%              	PidParent!{stopped,Pid};
%              {renamed,NProcess,NRenaming} -> 
%              	loop(NProcess,PidParent,NGraphParent,NPendingSC,NRenaming);
%              NProcess ->
%              	%io:format("Loop (~p) from ~p to ~p \n",[get_self(),Process,NProcess]),
%              	loop(NProcess,PidParent,NGraphParent,NPendingSC,Renaming)
%         end.
        
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Process Function
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% process({prefix,_,Channels,Event,Process,_}=Prefixing,PidParent,GraphParent,Renaming) -> 
% 	ExecutedEvent = rename_event(Event,Renaming),
% 	% io:format("\tProcess: ~p\n", [Channels]),
% 	% io:format("Prefixing in ~p: ~p\n", [self(), {Channels,Event}]),
% 	prefixing_loop(PidParent,Prefixing,Process,GraphParent,
% 	              {event,ExecutedEvent,Channels,get_self(),get_self(),Prefixing,GraphParent},
% 	              Channels);
% process({'|~|',PA,PB,_}, PidParent ,_,_) ->
% 	process_choice(PA,PB,true, PidParent);
% process({'[]',PA,PB,_},PidParent,GraphParent,Renaming) ->
%     {PA_,PB_} = random_branches(PA,PB),
% 	process_external_choice([PA_,PB_],PidParent,GraphParent,Renaming);
% 	% process_external_choice(PA_,PB_,PidParent,GraphParent,Renaming);
% process({'ifte',Condition,PA,PB,_,_,_},_,_,_) ->
% 	Event = list_to_atom("   tau -> Condition Choice value "++atom_to_list(Condition)),
% 	send_message2regprocess(printer,{print,Event,get_self()}),
% 	receive
% 		{printed,Event} -> ok
% 	end,
% 	case Condition of
% 	     true -> PA;
% 	     false -> PB
% 	end;
% process(AC = {agent_call,_,ProcessName,Arguments}, PidParent, _, _) ->
%    	Event = 
%    		list_to_atom("   tau -> Call to process " ++ atom_to_list(ProcessName)
% 		++ printer:string_arguments(Arguments)),
% 	Msg = {event,Event,[],get_self(),get_self(),none,none},
% 	process_call_loop(PidParent, AC, Msg);
% process({sharing,{closure,Events},PA,PB,_},PidParent,GraphParent,Renaming) ->
%     {PA_,PB_} = 
%     	random_branches(PA,PB),
% 	process_parallelism(PA_,PB_,Events,PidParent,GraphParent,Renaming);
% process({'|||',PA,PB,_},PidParent,GraphParent,Renaming) ->
%         {PA_,PB_} = random_branches(PA,PB),
% 	process_parallelism(PA_,PB_,[],PidParent,GraphParent,Renaming);
% process({procRenaming,ListRenamings,P,_},_,_,Renaming) ->
% 	{renamed,P,[ListRenamings|Renaming]};
% process({'\\',P,{closure,Events},_},_,_,Renaming) ->
% 	{renamed,P,[[{rename,Event,'   tau -> Hidding'}] || Event <- Events] ++ Renaming};
% process({stop,_},_,_,_) ->
% 	send_message2regprocess(printer,{print,'   tau -> STOP',get_self()}),
% 	receive
% 		{printed,'   tau -> STOP'} -> {stopped,get_self()}
% 	end.


% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Process Call
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%	
	
% process_call_loop(Pid, AC = {agent_call,_,ProcessName,Arguments}, Msg) ->
% 	% io:format("\nEnvia a ~p el missatge ~p\n",[Pid,Message]),
% 	Pid!Msg,
% 	receive 
% 		{executed,_,_,_} ->
% 			% send_message2regprocess(printer, {print, Event, get_self()}),
% 			io:format("Seguix\n"),
% 			send_message2regprocess(codeserver, {ask_code, ProcessName, Arguments, get_self()}),
% 			receive
% 				{code_reply,Code} -> 
% 					ok
% 			end,
% 			Pid!{sync_info,[none]},
% 	        receive
% 	           continue -> 
% 	           		Code 
% 	        end
% 	end.


% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Prefixing 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
% prefixing_loop(Pid,Prefixing,Process,GraphParent,Message,Channels) ->
% 	% io:format("\nEnvia a ~p el missatge ~p\n",[Pid,Message]),
% 	Pid!Message,
% 	receive 
% 		{executed,_,Pid,SelectedChannels} ->
% 				% io:format("\tEXE_Chan: ~p\n\tEXE_SCHan: ~p\n",[Channels,SelectedChannels]),
% 				{event,ExecutedEvent,_,_,_,_,_} = Message,
% 		        Dict = createDict(Channels,SelectedChannels,ExecutedEvent),
% 		        NPrefixing = csp_parsing:replace_parameters(Prefixing,Dict),
% 		        % io:format("Dict: ~p\nAntes: ~p\nDespues: ~p\n",[Dict,Prefixing,NPrefixing]),
% 		        % io:format("ExecutedEvent: ~p\n",[ExecutedEvent]),
% 		        % io:format("SelectedChannels: ~p\n",[SelectedChannels]),
% 		        send_message2regprocess(printer,{create_graph,{renamed_event,ExecutedEvent,NPrefixing},GraphParent,get_self()}),
% 				{prefix,_,_,_,NProcess,_} = NPrefixing,
% 				receive
% 			           {created,NParent} -> 
% 					       Pid!{sync_info,[NParent-1]},
% 					       receive
% 					           continue -> ok 
% 					       end,
% 					       {NProcess,NParent}
% 				end;
%        	rejected ->
% 		%timer:sleep(50),
% 			% io:format("\nREJECTED ~p el missatge ~p\n",[Pid,Message]),
% 			prefixing_loop(Pid,Prefixing,Process,GraphParent,Message,Channels);
% 		rejected_all ->
% 		%timer:sleep(50),
% 			% io:format("\nREJECTED_ALL ~p el missatge ~p\n",[Pid,Message]),
% 			{{stopped,get_self()},GraphParent}
% 	end.
	
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Internal Choice 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% %Controlar que no quede una unica crida a esta funció	
% process_choice(PA, PB, PrintTau, Pid) ->
% 	Pid!{choice, get_self(), PA, PB},
% 	receive 
% 		{executed, Selected} -> 
% 			% rand:seed(exs64),
% 			% Selected = rand:uniform(2),
% 			io:format("Selected ~p\n", [Selected]),
% 			case PrintTau of
% 			     true ->
% 				Event = list_to_atom("   tau -> Internal Choice. Branch " ++ integer_to_list(Selected)),
% 				send_message2regprocess(printer,{print,Event,get_self()}),
% 				receive
% 					{printed,Event} -> ok
% 				end;
% 			     false ->
% 			      	ok
% 			end, 
% 			NProcess = 
% 				case Selected of
% 				     1 -> PA;
% 				     2 -> PB
% 				end,
% 		   Pid!{sync_info,[none]},
% 	       receive
% 	           continue -> ok 
% 	       end,
% 	       NProcess
% 	end.
	
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Parallelisms
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
% process_parallelism(PA,PB,Events,PidParent,GraphParent,Renaming) ->
% 	PidA = spawn(csp_process_interactive,loop,[PA,get_self(),GraphParent,[],[]]),
% 	PidB = spawn(csp_process_interactive,loop,[PB,get_self(),GraphParent,[],[]]),
% 	% io:format("Parallelisme fill de ~p: ~p\n",[get_self(),{PidA,PidB}]),
% 	parallelism_loop(PidA,PidB,Events,PidParent,[],Renaming,{{},{}}, none).
	
% parallelism_loop(PidA,PidB,SyncEvents,PidParent,Finished,Renaming,TemporalGraphs, OtherBranchEvent) ->
% 	% io:format("LOOP Parallelisme fill de ~p: ~p\n",[get_self(),{PidA,PidB}]),
% 	case length([Fin || Fin = {_,NodesFinished} <- Finished, NodesFinished =/=[]]) of
% 	     2 -> 
% 	       % io:format("FIN Parallelisme fill de ~p: ~p\n",[get_self(),{PidA,PidB}]),
% 	       {finished,get_self(),lists:append([NodesFinished || 
% 		                              {_,NodesFinished} <- Finished])};
% %	       send_message2regprocess(printer,{print,tick_SP,get_self()}),
% %	       receive
% %		      {printed,tick_SP} -> 
% %		         {finished,get_self(),
% %		                   lists:append([NodesFinished || 
% %		                                 {_,NodesFinished} <- Finished])}
% %	       end;
% 	     _ ->
% 	     	case length(Finished) of
% 	     		  2 -> 
% 	     		  	{stopped,get_self()};
% 	     		  _ -> 
% 	     		  	% io:format("A la escolta SP ~p\n",[get_self()]),
% 					receive
% 					   {finished_skip,SPANSKIP,GraphParentSkip,PidSkip,PidAorB,true} -> 
% 					   		Send = 
% 						      case length([Fin || Fin = {_,NodesFinished} <- Finished, 
% 						      						NodesFinished =/=[]]) of
% 							   1 -> 
% 							       PidParent!{finished_skip,SPANSKIP,GraphParentSkip,
% 							                  PidSkip,get_self(),true};
% 							   _ -> 
% 							       PidParent!{finished_skip,SPANSKIP,GraphParentSkip,
% 							                  PidSkip,get_self(),false} 
% 						      end,
% 					      receive
% 					        {finished,PidAorB,NodesFinished} ->
% 					           parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                            [{PidAorB,NodesFinished}|Finished],
% 					                            Renaming,TemporalGraphs, OtherBranchEvent);
% 					        Other ->
% 					        	self()!Other,
% 					        	parallelism_loop(PidA,PidB,SyncEvents,PidParent,Finished,Renaming,TemporalGraphs, OtherBranchEvent)
% 					      end;
% 					   {finished_skip,_,_,_,_,false} = Message ->
% 					      PidParent!Message,
% 					      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                        Finished,Renaming,TemporalGraphs, OtherBranchEvent);
% 					   {finished,PidA,NodesFinished} ->
% 					      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                        [{PidA,NodesFinished}|Finished]
% 					                        ,Renaming,TemporalGraphs, OtherBranchEvent);
% 					   {finished,PidB,NodesFinished} ->
% 					      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 					                       [{PidB,NodesFinished}|Finished],
% 					                       Renaming,TemporalGraphs, OtherBranchEvent);
% 					   {stopped,PidA} ->
% 			 		      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 			                       [{PidA,[]}|Finished],
% 			                       Renaming,TemporalGraphs, OtherBranchEvent);
% 			 		   {stopped,PidB} ->
% 			 		      parallelism_loop(PidA,PidB,SyncEvents,PidParent,
% 			                       [{PidB,[]}|Finished],
% 			                       Renaming,TemporalGraphs, OtherBranchEvent);
% 					   % {event,_,_,PidA,_,_,_} = Message ->
% 					   {events_list,PidA,_} = Message ->
% 					       parallelism_event(Message,PidA,PidB,SyncEvents,
% 					   	                  PidParent,Finished,Renaming,TemporalGraphs);
% 					   % {event,_,_,PidB,_,_,_} = Message ->
% 					   {events_list,PidB,_} = Message ->
% 					   		parallelism_event(Message,PidA,PidB,SyncEvents,
% 					   	                  PidParent,Finished,Renaming,TemporalGraphs)        
% 					end
% 	     	end 
% 	end.

% {event,Event,Channels,Pid,[[{PidPrefixing,Prefixing,GraphParent}]]}


% parallelism_event({event,Event,Channels,Pid,PidPrefixing,Prefixing,GraphParent},PidA,PidB,
%                   SyncEvents,PidParent,Finished,Renaming,TemporalGraphs) ->
% 	% io:format("\tparallelism: ~p\n", [Channels]),
% 	% io:format("Event Parallelisme ~p: ~p\n",[{PidA,PidB}, Event]),
% 	ExecutedEvent = rename_event(Event,Renaming),
% 	Pids = 
% 		case Pid =:= PidA of
% 		    true ->
% 		    	{PidA,PidB};
% 		    false ->
% 		    	{PidB,PidA}
% 		end, 
% 	NTemporalGraphs =  
% 		process_event(Event,ExecutedEvent,Pids,PidPrefixing,   
% 	                 Channels,SyncEvents,PidParent,
% 	                 Prefixing,GraphParent,
% 	                 TemporalGraphs,PidA,PidB,
% 	                 Finished),      
% 	parallelism_loop(PidA,PidB,SyncEvents,PidParent,
%                  Finished,Renaming,NTemporalGraphs).

% process_event(Event,ExecutedEvent,{PidA,PidB},PidPrefixingA,ChannelsA,
%               SyncEvents,PidParent,PrefixingA,GraphParentA,
%               TemporalGraphs,PidAOri,PidBOri,Finished) ->
%        % io:format("SP ~p processa event ~p enviat per ~p\n",
%        %           [get_self(),Event,PidA]),
% 	case lists:member(Event,SyncEvents) of
% 	     true ->
% 	       	NTemporalGraphs_ = remove_temporal_graph(PidA,TemporalGraphs),
%         	NTemporalGraphs = create_temporal_graph(PidA,NTemporalGraphs_,PrefixingA,
%                                                 GraphParentA,PidAOri,PidBOri),
% 	        case length(Finished) of
% 	             1 -> 
% 	             	PidA!rejected_all,
% 			  		NTemporalGraphs;
% 	             _ -> 
% 	              	receive
% 	              	    {event,Event,ChannelsB,PidB,PidPrefixingB,_,_} -> 
% 	              	    	% io:format("\t\tChannelsA: ~p\n\t\tChannelsB: ~p\n\t\tCreate: ~p\n",[ChannelsA,ChannelsB,create_channels(ChannelsA,ChannelsB,[])]),     
% 	              	        case create_channels(ChannelsA,ChannelsB,[]) of
% 	              	             no_compatible ->
% 	              	                PidA!rejected,
% 							        PidB!rejected,
% 							        NTemporalGraphs;
% 				     			SelectedChannels ->   	              	    		  
% 									process_both_branches(ExecutedEvent,
% 									        PidA,PidPrefixingA,
% 									        PidB,PidPrefixingB,
% 									        SelectedChannels,
% 						                    PidParent,NTemporalGraphs)
% 	              	        end
% 	              	after 
% 	              	    0 -> 
% 	              	    	receive
% 	              	    	   {event,Event,ChannelsB,PidB,PidPrefixingB,_,_} ->
% 	              	    	   	% io:format("\t\tChannelsA: ~p\n\t\tChannelsB: ~p\n\t\tCreate: ~p\n",[ChannelsA,ChannelsB,create_channels(ChannelsA,ChannelsB,[])]),     
% 		              	    	case create_channels(ChannelsA,ChannelsB,[]) of
% 		              	            no_compatible ->
% 		              	                PidA!rejected,
% 					        			PidB!rejected,
% 					        			NTemporalGraphs;
% 					     			SelectedChannels ->   	              	    	  
% 										process_both_branches(ExecutedEvent,
% 										        PidA,PidPrefixingA,
% 										        PidB,PidPrefixingB,
% 										        SelectedChannels,
% 							                    PidParent,NTemporalGraphs)
% 		              	        end;
% 			                   Message ->
% 			                        PidA!rejected,
% 			                   		get_self()!Message,
% 			                   		NTemporalGraphs		                   
% 	              	    	end
% 	              	end
% 	        end;
%    	     false -> 
%    	         PidParent!{event,ExecutedEvent,ChannelsA,get_self(),
%    	                    PidPrefixingA,PrefixingA,GraphParentA},
%                  receive
%                    {executed,PidPrefixingA,PidParent,SelectedChannels} -> 
%                       NTemporalGraphs = remove_temporal_graph(PidA,TemporalGraphs),
%                       PidA!{executed,PidPrefixingA,get_self(),SelectedChannels},
%                       receive
%                          {sync_info,_} = Message ->
%                             PidParent ! Message
%                       end,
%                       NTemporalGraphs
%                    % rejected ->
%                    %    PidA!rejected,
%                    %    TemporalGraphs
%                   end
% 	end.

% process_both_branches(ExecutedEvent,PidA,PidPrefixingA,PidB,PidPrefixingB,
%                       SelectedChannels,PidParent,NTemporalGraphs) ->	
% 	PidParent!{event,ExecutedEvent,SelectedChannels,get_self(),get_self(),{},-1},
% 	receive
% 	   {executed,_,PidParent,FinallySelectedChannels} ->
% 	       NNTemporalGraphs_ = remove_temporal_graph(PidA,NTemporalGraphs),
% 	       NNTemporalGraphs = remove_temporal_graph(PidB,NNTemporalGraphs_),
% 	       PidA!{executed,PidPrefixingA,get_self(),FinallySelectedChannels},
% 	       PidB!{executed,PidPrefixingB,get_self(),FinallySelectedChannels},
% 	       receive
% 	           {sync_info,NodesA} ->
% 	              ok
% 	       end,
% 	       receive
% 	           {sync_info,NodesB} ->
% 	              ok
% 	       end,
% 	       PidPrefixingA!continue,
% 	       PidPrefixingB!continue,
% 	       [print_sync(NodeA,NodeB) || NodeA <- NodesA, 
% 		                           NodeB <- NodesB],
% 	       PidParent!{sync_info,NodesA ++ NodesB},
% 	       receive
% 	           continue -> ok
% 	       end,
% 	       NNTemporalGraphs
% 	   % rejected -> 
% 	   %   PidA!rejected,
% 	   %   PidB!rejected,
% 	   %   NTemporalGraphs;
% 	   % rejected_all -> 
% 	   %   PidA!rejected_all,
% 	   %   PidB!rejected_all,
% 	   %   NTemporalGraphs
% 	end.	

% print_sync(NodeA,NodeB) ->
% 	send_message2regprocess(printer,{print_sync,NodeA,NodeB,get_self()}),
% 	receive
%            {printed_sync,NodeA,NodeB} ->
%    	       ok
% 	end.
	
	
% create_channels([],[],FinalChannels) -> 
% 	lists:reverse(FinalChannels);
% create_channels([{out,Channel}|CA],[{in,_}|CB],FinalChannels) ->
% 	create_channels(CA,CB,[{out,Channel}|FinalChannels]);
% create_channels([{out,Channel}|CA],[{'inGuard',_,Channels}|CB],FinalChannels) ->
% 	case lists:member(Channel,Channels) of
% 	     true -> create_channels(CA,CB,[{out,Channel}|FinalChannels]);
% 	     false -> no_compatible
% 	end;
% create_channels([{out,ChannelA}|CA],[{out,ChannelB}|CB],FinalChannels) ->
% 	case ChannelA=:=ChannelB of
% 	     true -> create_channels(CA,CB,[{out,ChannelA}|FinalChannels]);
% 	     false -> no_compatible
% 	end;
% create_channels([{in,_}|_],[{in,_}|_],_) ->
% 	no_compatible;
% create_channels([{in,_}|CA],[{'inGuard',Var,Channels}|CB],FinalChannels) ->
% 	create_channels(CA,CB,[{'inGuard',Var,Channels}|FinalChannels]);
% create_channels([{'inGuard',Var,ChannelsA}|CA],[{'inGuard',_,ChannelsB}|CB],FinalChannels) ->
% 	Intersection = 
% 	   sets:tolist(sets:intersection(sets:from_list(ChannelsA),sets:from_list(ChannelsB))),
% 	case Intersection of
% 	     [] -> no_compatible;
% 	     _ -> 
% 	       create_channels(CA,CB,[{'inGuard',Var,Intersection}|FinalChannels])
% 	end;
% create_channels(ChannelsA,ChannelsB,FinalChannels) ->
% 	create_channels(ChannelsB,ChannelsA,FinalChannels).

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   External Choices 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	
% process_external_choice(PList0,PidParent,GraphParent,Renaming) ->
% 	PList = 
% 	% From: http://stackoverflow.com/a/8820501/4162959
% 		[X || {_,X} <- lists:sort(
% 			[ {rand:uniform(), P} || P <- PList0])],
% 	PidList = 
% 		[spawn(csp_process_interactive,loop,[P,get_self(),GraphParent,[],[]]) 
% 	 	 || P <- PList],
% 	external_choice_loop(PidList,PidParent,Renaming).
	

% external_choice_loop(PidList,PidParent,Renaming) ->
% 	% io:format("External choice ~p -> ~p\n", [self(), PidList]),
% 	receive
% 	   {finished_skip,SPANSKIP,GraphParentSkip,PidSkip,Pid,true} ->
% 	   		case lists:member(Pid, PidList) of 
% 	   			true -> 
% 					PidParent!
% 						{finished_skip,
% 							SPANSKIP,GraphParentSkip,
% 							PidSkip,get_self(),true},
% 					receive
% 						{finished,Pid,NodesFinished} -> 
% 						   	case PidList of 
% 						   	 	[Pid] ->
% 						   	 		{finished,get_self(),NodesFinished};
% 						   	 	_ ->
% 						   	 		finish_external_choice(NodesFinished)
% 						   	 end
% 					end;
% 				false -> 
% 					external_choice_loop(PidList,PidParent,Renaming)
% 			end;
% 	   {finished_skip,SPANSKIP,GraphParentSkip,PidSkip,Pid,false} ->
% 		   	case lists:member(Pid,PidList) of 
% 		   		true ->
% 				    PidParent!
% 				    	{finished_skip,
% 				    		SPANSKIP,GraphParentSkip,
% 				    		PidSkip,get_self(),false},
% 				    external_choice_loop(PidList,PidParent,Renaming);
% 				false ->
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end;
% 	   {finished,Pid,NodesFinished} ->
% 	   		case lists:member(Pid,PidList) of
% 	   			true ->
% 					case PidList of 
% 						[Pid] ->
% 							{finished,get_self(),NodesFinished};
% 						_ ->
% 							finish_external_choice(NodesFinished)
% 					end; 
% 				false -> 
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end;
% 	   {stopped,Pid} ->
% 	   		case lists:member(Pid,PidList) of
% 	   			true ->
% 					NPidList = PidList -- [Pid], 
% 					case NPidList of 
% 						[] -> 
% 							{stopped,get_self()};
% 						_ -> 
% 							external_choice_loop(NPidList,PidParent,Renaming) 
% 					end;
% 				false -> 
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end;
% 	   {event,Event,Channels,Pid,PidPrefixing,Prefixing,GraphParent} ->
% 	   		% io:format("External choice ~p -> received event ~p\n", [self(), {Event,Pid}]),
% 		   	case lists:member(Pid,PidList) of
% 	   			true ->	
% 					ExecutedEvent = rename_event(Event,Renaming),
% 					% io:format("External choice ~p -> envia a parent ~p\n", [self(), {Event,PidParent}]),
% 					PidParent!
% 						{event,
% 							ExecutedEvent,Channels,get_self(),
% 							PidPrefixing,Prefixing,GraphParent},
% 					process_event_ec(
% 						Renaming,PidPrefixing,PidParent,Pid,PidList);
% 				false ->
% 					external_choice_loop(PidList,PidParent,Renaming) 
% 			end
% 	end.	
       
% process_event_ec(Renaming,PidPrefixing,PidParent,Pid,PidList) ->
% 	% io:format("Receiving event ~p\n", [self()]),
% 	receive
% 		{executed,PidPrefixing,PidParent,SelectedChannels} -> 
% 			Pid!{executed,PidPrefixing,get_self(),SelectedChannels},
% 			receive
% 			 	{sync_info,_} = Message ->
% 			    	PidParent ! Message
% 			end,
% 			% io:format("One process ~p -> ~p\n", [self(), Pid]),
% 	      	external_choice_loop([Pid],PidParent,Renaming);
% 		rejected -> 
% 			Pid!rejected,
% 			external_choice_loop(PidList,PidParent,Renaming);
% 		rejected_all -> 
% 			Pid!rejected_all,
% 			external_choice_loop(PidList,PidParent,Renaming)
% 	end.

% finish_external_choice(NodesFinished) ->
% 	send_message2regprocess(printer,{print,tick_EC,get_self()}),
% 	receive
% 	  {printed,tick_EC} -> 
% 	     {finished,get_self(),NodesFinished}
% 	end.

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %   Other Functions
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	
% rename_event(Event,[List|TailRenaming]) ->
% 	rand:seed(exs64),
% 	ShuffledList = 
% 		[X || {_,X} <- lists:sort([ {rand:uniform(), N} || N <- List])],
% 	rename_event(rename_event_list(Event,ShuffledList),TailRenaming);
% % rename_event(Event,[_|TailRenaming]) ->
% % 	rename_event(Event,TailRenaming);
% rename_event(Event,[]) -> 
% 	Event.

% rename_event_list(Event,[{rename,Event,Renamed}|_]) ->
% 	Renamed;
% rename_event_list(Event,[_|Tail]) ->
% 	rename_event_list(Event,Tail);
% rename_event_list(Event,[]) ->
% 	Event.

% %vore que no quede una unica cria a aquesta funció
% print_skip(SPAN,GraphParent,PidSkip,IsFinal) ->	
% 	send_message2regprocess(printer,{create_graph,{skip,SPAN},GraphParent,get_self()}),
% 	NGraphParent = 
% 		receive
% 		   {created,NGraphParent_} -> NGraphParent_
% 		end,
% 	case IsFinal of
% 	     true -> send_message2regprocess(printer,{print,'   tick',get_self()});
% 	     false -> send_message2regprocess(printer,{print,'   tau',get_self()})
% 	end,
% 	receive
% 	   {printed,'   tick'} -> 
% 		  ok;
%            {printed,'   tau'} -> 
% 		  ok
% 	end,
% 	PidSkip!{continue_skip,NGraphParent}.
	
% remove_temporal_graph(Pid,TemporalGraphs) ->	
%         case TemporalGraphs of
%              {{Pid,IdAno},Other} ->
% 				send_message2regprocess(printer,{remove_graph_no_ided,IdAno,get_self()}),
% 				receive
% 				    {removed,IdAno} ->
% 				    	{{},Other}
% 				end;
%              {Other,{Pid,IdAno}} ->
% 				send_message2regprocess(printer,{remove_graph_no_ided,IdAno,get_self()}),
% 				receive
% 				    {removed,IdAno} ->
% 				    	{Other,{}}
% 				end;
%              _ -> 
%              	TemporalGraphs
%         end.
        
% create_temporal_graph(Pid,{TGraphA,TGraphB},Prefixing,GraphParent,PidA,PidB) ->	 
%     case Prefixing of 
%          {} ->
%             {TGraphA,TGraphB};
%          _ ->
% 			send_message2regprocess(printer,{create_graph_no_ided,Prefixing,GraphParent,get_self()}),
% 			receive
% 			    {created_no_id,IdAno} ->
% 			    	ok
% 			end,
% 			case Pid of
% 			     PidA ->
% 			        {{Pid,IdAno},TGraphB};
% 			     PidB ->
% 			     	{TGraphA,{Pid,IdAno}}
% 			end
% 	end.	
	
% random_branches(PA,PB) ->
% 	rand:seed(exs64),
% 	Selected = rand:uniform(2),
% 	case Selected of
% 		1 -> {PA,PB};
% 		2 -> {PB,PA}
% 	end. 

% select_channels([{out,Channel}|Tail],Event) ->
% 	% io:format("Event: ~p\nChannel: ~p\n",[Event,Channel]),	
% 	[Channel|select_channels(Tail,Event)];
% select_channels([{'inGuard',_,ChannelsList}|Tail],Event) ->
%         rand:seed(exs64),
%         Selected = rand:uniform(length(ChannelsList)),
% 	[lists:nth(Selected,ChannelsList)|select_channels(Tail,Event)];
% select_channels([{in,_}|Tail],Event) ->
% 	send_message2regprocess(codeserver,{ask_channel,Event,get_self()}),
% 	% io:format("Event: ~p\n",[Event]),
% 	% ChannelsR = 
% 	Channels = 
% 		receive
% 			{channel_reply,Channels_} -> Channels_
% 		end,
% 	% Channels = lists:reverse(ChannelsR),
% 	% io:format("Channels_: ~p\n",[Channels_]),
% 	NTail = 
% 		try 
% 			lists:sublist(Tail,length(Channels),length(Tail))
% 		catch
% 			_:_ -> []
% 		end,
% 	% io:format("Channels: ~p\n",[Channels]),
% 	Channels ++ select_channels(NTail,Event);
% select_channels(Other = [_|_],_) ->
% 	% io:format("Other type of channel: ~p\n",[Other]),
% 	[];
% select_channels([],_) ->
% 	[].
	
% create_channels_string([]) ->
% 	"";
% create_channels_string([Channel]) when is_integer(Channel) ->
% 	integer_to_list(Channel);
% create_channels_string([Channel]) when is_atom(Channel) ->
% 	atom_to_list(Channel);
% create_channels_string([Channel|Tail]) when is_integer(Channel) ->
% 	integer_to_list(Channel)++"."++create_channels_string(Tail);
% create_channels_string([Channel|Tail]) when is_atom(Channel) ->
% 	atom_to_list(Channel)++"."++create_channels_string(Tail).
	
% createDict([{'inGuard',Var,_}|TC],[Selected|TS],EE) when is_list(Var) ->
% 	[{list_to_atom(Var),Selected}|createDict(TC,TS,EE)];
% createDict([{'inGuard',Var,_}|TC],[Selected|TS],EE) when is_atom(Var) ->
% 	[{Var,Selected}|createDict(TC,TS,EE)];
% createDict([{in,Var}|TC],[Selected|TS],EE) when is_list(Var) ->
% 	[{list_to_atom(Var),Selected}|createDict(TC,TS,EE)];
% createDict([{in,Var}|TC],[Selected|TS],EE) when is_atom(Var) ->
% 	[{Var,Selected}|createDict(TC,TS,EE)];
% createDict([{in,_}|_],_,EE) ->
% 	throw(lists:flatten(io_lib:format("Detected an in-channel without defined options while executing event ~p", [EE])));
% createDict([{out,_}|TC],[_|TS],EE) ->
% 	createDict(TC,TS,EE);
% createDict([],[],_) ->
% 	[].

% send_message2regprocess(Process,Message) ->
%  	ProcessPid = whereis(Process),
%  	case ProcessPid of 
%  		undefined -> 
%  			no_sent;
%  		_ -> 
%          	case is_process_alive(ProcessPid) of 
%          		true -> 
% 			        ProcessPid!Message;
% 				false -> 
% 					no_sent
% 			end
% 	end.

% get_self() ->
% 	catch self().
