(*
 * (c) 2015 Andreas Rossberg
 *)

{
open Parser
open Ast

let convert_pos pos =
  { Source.file = pos.Lexing.pos_fname;
    Source.line = pos.Lexing.pos_lnum;
    Source.column = pos.Lexing.pos_cnum - pos.Lexing.pos_bol
  }

let region lexbuf =
  let left = convert_pos (Lexing.lexeme_start_p lexbuf) in
  let right = convert_pos (Lexing.lexeme_end_p lexbuf) in 
  {Source.left = left; Source.right = right}

let error lexbuf m = Error.error (region lexbuf) m
let error_nest start lexbuf m =
  lexbuf.Lexing.lex_start_p <- start;
  error lexbuf m

let convert_text s =
  let b = Buffer.create (String.length s) in
  let i = ref 1 in
  while !i < String.length s - 1 do
    let c = if s.[!i] <> '\\' then s.[!i] else
      match (incr i; s.[!i]) with
      | 'n' -> '\n'
      | 't' -> '\t'
      | '\\' -> '\\'
      | '\'' -> '\''
      | '\"' -> '\"'
      | d ->
        incr i;
        Char.chr (int_of_string ("0x" ^ String.make 1 d ^ String.make 1 s.[!i]))
    in Buffer.add_char b c;
    incr i
  done;
  Buffer.contents b

let value_type = function
  | "i32" -> Types.Int32Type
  | "i64" -> Types.Int64Type
  | "f32" -> Types.Float32Type
  | "f64" -> Types.Float64Type
  | _ -> assert false

let intop t i32 i64 =
  match t with
  | "i32" -> Values.Int32 i32
  | "i64" -> Values.Int64 i64
  | _ -> assert false

let floatop t f32 f64 =
  match t with
  | "f32" -> Values.Float32 f32
  | "f64" -> Values.Float64 f64
  | _ -> assert false

let mem_type mty =
  let open Memory in
  match mty with
  | "i8" -> Int8Mem
  | "i16" -> Int16Mem
  | "i32" -> Int32Mem
  | "i64" -> Int64Mem
  | "f32" -> Float32Mem
  | "f64" -> Float64Mem
  | _ -> assert false

let loadop t sign a =
  let mem = mem_type t in
  let ext = match sign with
    | ' ' -> Memory.NX
    | 's' -> Memory.SX
    | 'u' -> Memory.ZX
    | _ -> assert false in
  let align = if a = "" then Memory.mem_size mem else int_of_string a in
  {mem; ext; align}

let storeop t a =
  let mem = mem_type t in
  let align = if a = "" then Memory.mem_size mem else int_of_string a in
  {mem; align}
}

let space = [' ''\t']
let digit = ['0'-'9']
let hexdigit = ['0'-'9''a'-'f''A'-'F']
let letter = ['a'-'z''A'-'Z']
let symbol = ['+''-''*''/''\\''^''~''=''<''>''!''?''@''#''$''%''&''|'':''`']
let tick = '\''
let escape = ['n''t''\\''\'''\"']
let character = [^'"''\\''\n'] | '\\'escape | '\\'hexdigit hexdigit

let num = ('+' | '-')? digit+
let hexnum = ('+' | '-')? "0x" hexdigit+
let int = num | hexnum
let float = (num '.' digit+) | num ('.' digit+)? ('e' | 'E') num
let text = '"' character* '"'
let name = '$' (letter | digit | '_' | tick | symbol)+

let ixx = "i" ("32" | "64")
let fxx = "f" ("32" | "64")
let nxx = ixx | fxx
let mixx = "i" ("8" | "16" | "32" | "64")
let mfxx = "f" ("32" | "64")
let sign = "s" | "u"
let align = digit+
let width = digit+

rule token = parse
  | "(" { LPAR }
  | ")" { RPAR }
  | int as s { INT s }
  | float as s { FLOAT s }
  | text as s { TEXT (convert_text s) }
  | '"'character*('\n'|eof) { error lexbuf "unclosed text literal" }
  | '"'character*'\\'_
    { error_nest (Lexing.lexeme_end_p lexbuf) lexbuf "illegal escape" }

  | "i32" { TYPE Types.Int32Type }
  | "i64" { TYPE Types.Int64Type }
  | "f32" { TYPE Types.Float32Type }
  | "f64" { TYPE Types.Float64Type }

  | "nop" { NOP }
  | "block" { BLOCK }
  | "if" { IF }
  | "loop" { LOOP }
  | "label" { LABEL }
  | "break" { BREAK }
  | "case" { CASE }
  | "fallthrough" { FALLTHROUGH }
  | "call" { CALL }
  | "call_import" { CALLIMPORT }
  | "call_indirect" { CALLINDIRECT }
  | "return" { RETURN }

  | "get_local" { GETLOCAL }
  | "set_local" { SETLOCAL }

  | (nxx as t)".load" { LOAD (loadop t ' ' "") }
  | (nxx as t)".load/"(align as a) { LOAD (loadop t ' ' a) }
  | (ixx)".load"(width as w)"_"(sign as s) { LOAD (loadop ("i" ^ w) s "") }
  | (ixx)".load"(width as w)"_"(sign as s)"/"(align as a) { LOAD (loadop ("i" ^ w) s a) }
  | (nxx as t)".store" { STORE (storeop t "") }
  | (nxx as t)".store/"(align as a) { STORE (storeop t a) }
  | (ixx)".store"(width as w) { STORE (storeop ("i" ^ w) "") }
  | (ixx)".store"(width as w)"/"(align as a) { STORE (storeop ("i" ^ w) a) }

  | (nxx as t)".switch" { SWITCH (value_type t) }
  | (nxx as t)".const" { CONST (value_type t) }

  | (ixx as t)".clz" { UNARY (intop t Int32Op.Clz Int64Op.Clz) }
  | (ixx as t)".ctz" { UNARY (intop t Int32Op.Ctz Int64Op.Ctz) }
  | (ixx as t)".popcnt" { UNARY (intop t Int32Op.Popcnt Int64Op.Popcnt) }
  | (fxx as t)".neg" { UNARY (floatop t Float32Op.Neg Float64Op.Neg) }
  | (fxx as t)".abs" { UNARY (floatop t Float32Op.Abs Float64Op.Abs) }
  | (fxx as t)".sqrt" { UNARY (floatop t Float32Op.Sqrt Float64Op.Sqrt) }
  | (fxx as t)".ceil" { UNARY (floatop t Float32Op.Ceil Float64Op.Ceil) }
  | (fxx as t)".floor" { UNARY (floatop t Float32Op.Floor Float64Op.Floor) }
  | (fxx as t)".trunc" { UNARY (floatop t Float32Op.Trunc Float64Op.Trunc) }
  | (fxx as t)".nearest"
    { UNARY (floatop t Float32Op.Nearest Float64Op.Nearest) }

  | (ixx as t)".add" { BINARY (intop t Int32Op.Add Int64Op.Add) }
  | (ixx as t)".sub" { BINARY (intop t Int32Op.Sub Int64Op.Sub) }
  | (ixx as t)".mul" { BINARY (intop t Int32Op.Mul Int64Op.Mul) }
  | (ixx as t)".div_s" { BINARY (intop t Int32Op.DivS Int64Op.DivS) }
  | (ixx as t)".div_u" { BINARY (intop t Int32Op.DivU Int64Op.DivU) }
  | (ixx as t)".rem_s" { BINARY (intop t Int32Op.RemS Int64Op.RemS) }
  | (ixx as t)".rem_u" { BINARY (intop t Int32Op.RemU Int64Op.RemU) }
  | (ixx as t)".and" { BINARY (intop t Int32Op.And Int64Op.And) }
  | (ixx as t)".or" { BINARY (intop t Int32Op.Or Int64Op.Or) }
  | (ixx as t)".xor" { BINARY (intop t Int32Op.Xor Int64Op.Xor) }
  | (ixx as t)".shl" { BINARY (intop t Int32Op.Shl Int64Op.Shl) }
  | (ixx as t)".shr_u" { BINARY (intop t Int32Op.ShrU Int64Op.ShrU) }
  | (ixx as t)".shr_s" { BINARY (intop t Int32Op.ShrS Int64Op.ShrS) }
  | (fxx as t)".add" { BINARY (floatop t Float32Op.Add Float64Op.Add) }
  | (fxx as t)".sub" { BINARY (floatop t Float32Op.Sub Float64Op.Sub) }
  | (fxx as t)".mul" { BINARY (floatop t Float32Op.Mul Float64Op.Mul) }
  | (fxx as t)".div" { BINARY (floatop t Float32Op.Div Float64Op.Div) }
  | (fxx as t)".min" { BINARY (floatop t Float32Op.Min Float64Op.Min) }
  | (fxx as t)".max" { BINARY (floatop t Float32Op.Max Float64Op.Max) }
  | (fxx as t)".copysign"
    { BINARY (floatop t Float32Op.CopySign Float64Op.CopySign) }

  | (ixx as t)".eq" { COMPARE (intop t Int32Op.Eq Int64Op.Eq) }
  | (ixx as t)".ne" { COMPARE (intop t Int32Op.Ne Int64Op.Ne) }
  | (ixx as t)".lt_s" { COMPARE (intop t Int32Op.LtS Int64Op.LtS) }
  | (ixx as t)".lt_u" { COMPARE (intop t Int32Op.LtU Int64Op.LtU) }
  | (ixx as t)".le_s" { COMPARE (intop t Int32Op.LeS Int64Op.LeS) }
  | (ixx as t)".le_u" { COMPARE (intop t Int32Op.LeU Int64Op.LeU) }
  | (ixx as t)".gt_s" { COMPARE (intop t Int32Op.GtS Int64Op.GtS) }
  | (ixx as t)".gt_u" { COMPARE (intop t Int32Op.GtU Int64Op.GtU) }
  | (ixx as t)".ge_s" { COMPARE (intop t Int32Op.GeS Int64Op.GeS) }
  | (ixx as t)".ge_u" { COMPARE (intop t Int32Op.GeU Int64Op.GeU) }
  | (fxx as t)".eq" { COMPARE (floatop t Float32Op.Eq Float64Op.Eq) }
  | (fxx as t)".ne" { COMPARE (floatop t Float32Op.Ne Float64Op.Ne) }
  | (fxx as t)".lt" { COMPARE (floatop t Float32Op.Lt Float64Op.Lt) }
  | (fxx as t)".le" { COMPARE (floatop t Float32Op.Le Float64Op.Le) }
  | (fxx as t)".gt" { COMPARE (floatop t Float32Op.Gt Float64Op.Gt) }
  | (fxx as t)".ge" { COMPARE (floatop t Float32Op.Ge Float64Op.Ge) }

  | "i64.extend_s/i32" { CONVERT (Values.Int64 Int64Op.ExtendSInt32) }
  | "i64.extend_u/i32" { CONVERT (Values.Int64 Int64Op.ExtendUInt32) }
  | "i32.wrap/i64" { CONVERT (Values.Int32 Int32Op.WrapInt64) }
  | (ixx as t)".trunc_s/f32"
    { CONVERT (intop t Int32Op.TruncSFloat32 Int64Op.TruncSFloat32) }
  | (ixx as t)".trunc_u/f32"
    { CONVERT (intop t Int32Op.TruncUFloat32 Int64Op.TruncUFloat32) }
  | (ixx as t)".trunc_s/f64"
    { CONVERT (intop t Int32Op.TruncSFloat64 Int64Op.TruncSFloat64) }
  | (ixx as t)".trunc_u/f64"
    { CONVERT (intop t Int32Op.TruncUFloat64 Int64Op.TruncUFloat64) }
  | (fxx as t)".convert_s/i32"
    { CONVERT (floatop t Float32Op.ConvertSInt32 Float64Op.ConvertSInt32) }
  | (fxx as t)".convert_u/i32"
    { CONVERT (floatop t Float32Op.ConvertUInt32 Float64Op.ConvertUInt32) }
  | (fxx as t)".convert_s/i64"
    { CONVERT (floatop t Float32Op.ConvertSInt64 Float64Op.ConvertSInt64) }
  | (fxx as t)".convert_u/i64"
    { CONVERT (floatop t Float32Op.ConvertUInt64 Float64Op.ConvertUInt64) }
  | "f64.promote/f32" { CONVERT (Values.Float64 Float64Op.PromoteFloat32) }
  | "f32.demote/f64" { CONVERT (Values.Float32 Float32Op.DemoteFloat64) }
  | "f32.reinterpret/i32" { CONVERT (Values.Float32 Float32Op.ReinterpretInt) }
  | "f64.reinterpret/i64" { CONVERT (Values.Float64 Float64Op.ReinterpretInt) }
  | "i32.reinterpret/f32" { CONVERT (Values.Int32 Int32Op.ReinterpretFloat) }
  | "i64.reinterpret/f64" { CONVERT (Values.Int64 Int64Op.ReinterpretFloat) }

  | "page_size" { PAGESIZE }
  | "memory_size" { MEMORYSIZE }
  | "resize_memory" { RESIZEMEMORY }

  | "func" { FUNC }
  | "param" { PARAM }
  | "result" { RESULT }
  | "local" { LOCAL }
  | "module" { MODULE }
  | "memory" { MEMORY }
  | "segment" { SEGMENT }
  | "import" { IMPORT }
  | "export" { EXPORT }
  | "table" { TABLE }

  | "assert_invalid" { ASSERTINVALID }
  | "assert_eq" { ASSERTEQ }
  | "assert_trap" { ASSERTTRAP }
  | "invoke" { INVOKE }

  | name as s { VAR s }

  | ";;"[^'\n']*eof { EOF }
  | ";;"[^'\n']*'\n' { Lexing.new_line lexbuf; token lexbuf }
  | "(;" { comment (Lexing.lexeme_start_p lexbuf) lexbuf; token lexbuf }
  | space { token lexbuf }
  | '\n' { Lexing.new_line lexbuf; token lexbuf }
  | eof { EOF }
  | _ { error lexbuf "unknown opcode" }

and comment start = parse
  | ";)" { () }
  | "(;" { comment (Lexing.lexeme_start_p lexbuf) lexbuf; comment start lexbuf }
  | '\n' { Lexing.new_line lexbuf; comment start lexbuf }
  | eof { error_nest start lexbuf "unclosed comment" }
  | _ { comment start lexbuf }
