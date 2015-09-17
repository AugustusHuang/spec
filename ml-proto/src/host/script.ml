(*
 * (c) 2015 Andreas Rossberg
 *)

open Source

(* Script representation *)

type command = command' phrase
and command' =
  | Define of Ast.modul
  | AssertInvalid of Ast.modul * string
  | Invoke of string * Ast.expr list
  | AssertEq of string * Ast.expr list * Ast.expr
  | AssertEqBits of string * Ast.expr list * Ast.expr
  | AssertNaN of string * Ast.expr list
  | AssertFault of string * Ast.expr list * string

type script = command list


(* Execution *)

let trace name = if !Flags.trace then print_endline ("-- " ^ name)

let current_module : Eval.instance option ref = ref None

let eval_args es at =
  let evs = List.map Eval.eval es in
  let reject_none = function
    | Some v -> v
    | None -> Error.error at "unexpected () value" in
  List.map reject_none evs

let get_module at = match !current_module with
  | Some m -> m
  | None -> Error.error at "no module defined to invoke"

let show_value label v = begin
  print_string (label ^ ": ");
  Print.print_value v
end

let show_result got_v = begin
  show_value "Result" got_v
end

let show_result_expect got_v expect_v = begin
  show_result got_v;
  show_value "Expect" expect_v
end

let assert_error f err re at =
  match f () with
  | exception Error.Error (_, s) ->
    if not (Str.string_match (Str.regexp re) s 0) then
      Error.error at ("failure \"" ^ s ^ "\" does not match: \"" ^ re ^ "\"")
  | _ ->
    Error.error at ("expected " ^ err)

let run_command cmd =
  match cmd.it with
  | Define m ->
    trace "Checking...";
    Check.check_module m;
    if !Flags.print_sig then begin
      trace "Signature:";
      Print.print_module_sig m
    end;
    trace "Initializing...";
    let imports = Builtins.match_imports m.it.Ast.imports in
    current_module := Some (Eval.init m imports)

  | AssertInvalid (m, re) ->
    trace "Checking invalid...";
    assert_error (fun () -> Check.check_module m) "invalid module" re cmd.at

  | Invoke (name, es) ->
    trace "Invoking...";
    let m = get_module cmd.at in
    let vs = eval_args es cmd.at in
    let v = Eval.invoke m name vs in
    if v <> None then Print.print_value v

  | AssertEq (name, arg_es, expect_e) ->
    let open Values in
    trace "AssertEq invoking...";
    let m = get_module cmd.at in
    let arg_vs = eval_args arg_es cmd.at in
    let got_v = Eval.invoke m name arg_vs in
    let expect_v = Eval.eval expect_e in
    (match got_v, expect_v with
     | Some Int32 got_i32, Some Int32 expect_i32 ->
       if got_i32 <> expect_i32 then begin
         show_result_expect got_v expect_v;
         Error.error cmd.at "assert_eq i32 operands are not equal"
       end
     | Some Int64 got_i64, Some Int64 expect_i64 ->
       if got_i64 <> expect_i64 then begin
         show_result_expect got_v expect_v;
         Error.error cmd.at "assert_eq i64 operands are not equal"
       end
     | _, _ -> begin
         show_result_expect got_v expect_v;
         Error.error cmd.at "assert_eq operands must be both i32 or both i64"
       end)

  | AssertEqBits (name, arg_es, expect_e) ->
    let open Values in
    trace "AssertEqBits invoking...";
    let m = get_module cmd.at in
    let arg_vs = eval_args arg_es cmd.at in
    let got_v = Eval.invoke m name arg_vs in
    let expect_v = Eval.eval expect_e in
    (match got_v, expect_v with
     | Some Float32 got_f32, Some Float32 expect_f32 ->
       if (Float32.to_bits got_f32) <> (Float32.to_bits expect_f32) then begin
         show_result_expect got_v expect_v;
         Error.error cmd.at
                     "assert_eq_bits f32 operands have different bit patterns"
       end
     | Some Float64 got_f64, Some Float64 expect_f64 ->
       if (Float64.to_bits got_f64) <> (Float64.to_bits expect_f64) then begin
         show_result_expect got_v expect_v;
         Error.error cmd.at
                     "assert_eq_bits f64 operands have different bit patterns"
       end
     | _, _ -> begin
         show_result_expect got_v expect_v;
         Error.error cmd.at
                     "assert_eq_bits operands must be both f32 or both f64"
       end)

  | AssertNaN (name, arg_es) ->
    let open Values in
    trace "AssertNaN invoking...";
    let m = get_module cmd.at in
    let arg_vs = eval_args arg_es cmd.at in
    let got_v = Eval.invoke m name arg_vs in
    (match got_v with
     | Some Float32 got_f32 ->
       if (Float32.eq got_f32 got_f32) then begin
         show_result got_v;
         Error.error cmd.at "assert_nan f32 operand is not a NaN"
       end
     | Some Float64 got_f64 ->
       if (Float64.eq got_f64 got_f64) then begin
         show_result got_v;
         Error.error cmd.at "assert_nan f64 operand is not a NaN"
       end
     | _ -> begin
         show_result got_v;
         Error.error cmd.at "assert_nan operand must be f32 or f64"
       end)

  | AssertFault (name, es, re) ->
    trace "AssertFault invoking...";
    let m = get_module cmd.at in
    let vs = eval_args es cmd.at in
    assert_error (fun () -> Eval.invoke m name vs) "fault" re cmd.at

let dry_command cmd =
  match cmd.it with
  | Define m ->
    Check.check_module m;
    if !Flags.print_sig then Print.print_module_sig m
  | AssertInvalid _ -> ()
  | Invoke _ -> ()
  | AssertEq _ -> ()
  | AssertEqBits _ -> ()
  | AssertNaN _ -> ()
  | AssertFault _ -> ()

let run script =
  List.iter (if !Flags.dry then dry_command else run_command) script
