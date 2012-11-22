open Core
open Core.Std
open Parse
open Printf
open Helpers

open Parse.Yaml2
open Types

let ocaml_name_of_prop ~classname sort ({name;typ;_}) : string =
  sprintf "prop_%s_%s_%s_%s" classname name 
    (match sort with `Getter -> "get" | `Setter -> "set")
    (match typ  with 
      | `Float -> "float"
      | `Bool -> "bool"
      | `Unit  -> "void"
      | `String -> "string" | `Int -> "int" 
      | `Tuple lst -> sprintf "tuple%d" (List.length lst)
      | `List _ -> sprintf "xxxx_list")

let cpp_value_of_ocaml ch (get_var,release_var,new_cpp_var) ~cpp_var ~ocaml_var typ =
  let print_cpp fmt = fprintf ch fmt in
  let rec to_cpp_conv ~tab dest var typ =
      let prefix = String.concat ~sep:"" (List.init ~f:(fun _ -> "  ") tab) in
      match typ with
        | `Unit    -> ()
        | `Int     -> print_cpp "%s%s = Int_val(%s);\n" prefix dest var
        | `String  -> print_cpp "%s%s = QString(String_val(%s));\n" prefix dest var
        | `Bool    -> print_cpp "%s%s = Bool_val(%s);\n" prefix dest var
        | `Float   -> raise (Unimplemented "Floats are not implemented yet")
        | `Tuple xs when List.length xs <> 2 ->
            raise (Unimplemented "Again: tuples <> pairs")
        | `Tuple xs ->
            print_cpp "%s//generating: %s\n" prefix (TypAst.to_ocaml_type typ);
            let (a,b) = match xs with a::b::_ -> (a,b) | _ -> assert false in
            let leftV = new_cpp_var () in
            print_cpp "%s%s %s;\n" prefix (TypAst.to_cpp_type a) leftV;
            to_cpp_conv ~tab:(tab+1) leftV  (sprintf "Field(%s,0)" var) a;
            let rightV = new_cpp_var () in
            print_cpp "%s%s %s;\n" prefix (TypAst.to_cpp_type b) rightV;
            to_cpp_conv ~tab:(tab+1) rightV (sprintf "Field(%s,1)" var) b;
            print_cpp "%s%s = qMakePair(%s,%s);\n" prefix dest leftV rightV;
        | `List t ->
            print_cpp "%s//generating: %s\n" prefix (TypAst.to_ocaml_type typ);
            let cpp_arg_type = TypAst.to_cpp_type t in
            let temp_var = get_var () in
            let head_var = get_var () in
            let temp_cpp_var = new_cpp_var () in
            print_cpp "%s%s = %s;\n" prefix temp_var var;
            print_cpp "%swhile (%s != Val_emptylist) {\n" prefix temp_var;
            print_cpp "%s  %s = Field(%s,0); /* head */\n" prefix head_var temp_var;
            print_cpp "%s  %s %s;\n" prefix cpp_arg_type temp_cpp_var;
            to_cpp_conv ~tab:(tab+1) temp_cpp_var head_var t;
            print_cpp "%s  %s << %s;\n" prefix dest temp_cpp_var;
            print_cpp "%s}\n" prefix;
            release_var temp_var;
  in
  to_cpp_conv ~tab:1 cpp_var ocaml_var typ

let ocaml_value_of_cpp ~tab ch (get_var,release_var) ~ocamlvar ~cppvar typ =
  let print_cpp fmt = fprintf ch fmt in
  let rec generate_wrapper ~tab var dest typ : unit =
    (* tab is for left tabularies. typ is a type
     * dest is where to store generated value 
     * var is C++ variable to convert *)
    let prefix = String.concat ~sep:"" (List.init ~f:(fun _ -> "  ") tab) in
    print_cpp "%s" prefix;
    let () = match typ with
      | `Unit   -> raise (Bug "Can't be unit in a variable parameter")
      | `Int    -> print_cpp "%s%s = Val_int (%s); " prefix dest var
      | `Bool   -> print_cpp "%s%s = Val_bool(%s); " prefix dest var
      | `Float  -> raise (Unimplemented "float values are not yet implemented")
      | `String -> 
          print_cpp "%s%s = caml_copy_string(%s.toLocal8Bit().data() );" prefix dest var
      | `Tuple lst when List.length lst <> 2 -> 
          raise (Unimplemented "tuples are not fully implemented")
      | `Tuple xs ->
          let a = List.hd_exn xs and b = xs |> List.tl_exn |> List.hd_exn in
          print_cpp   "%s = caml_alloc (2,0);\n" dest;
          let leftV = get_var () in
          generate_wrapper ~tab:(tab+1) (var ^".first") leftV a;
          print_cpp "%s Store_field( %s, 0, %s);\n" prefix dest leftV;
          release_var leftV;
          let rightV = get_var () in
          generate_wrapper ~tab:(tab+1) (var ^".second") rightV b;
          print_cpp "%s Store_field( %s, 0, %s);\n" prefix dest rightV;
          release_var rightV;
      | `List typ -> 
          let cons_helper = get_var () in
          let cons_arg_var = get_var () in
          print_cpp "%s%s = Val_emptylist;\n" prefix dest;
          print_cpp "%sif ((%s).length != 0) {\n" prefix var;
          print_cpp "%s  auto it = (%s).end() - 1;\n" prefix var;
          print_cpp "%s  for (;;) {\n" prefix;
          print_cpp "%s    %s = caml_alloc(2,0);\n" prefix cons_helper;
          generate_wrapper ~tab:(tab+1)  "*it" cons_arg_var typ;
          print_cpp "%s    Store_field(%s, 0, %s);\n" prefix cons_helper cons_arg_var;
          print_cpp "%s    Store_field(%s, 1, %s);\n" prefix cons_helper dest;
          print_cpp "%s    %s = %s;\n" prefix dest cons_helper; 
          print_cpp "%s    if ((%s).begin() == it) break;\n" prefix var;
          print_cpp "%s    it--;\n" prefix;
          print_cpp "%s  }\n" prefix;
          print_cpp "%s}\n" prefix;
          release_var cons_arg_var;
          release_var cons_helper;
    in
    print_cpp "%s" "\n"
  in
  generate_wrapper ~tab cppvar ocamlvar typ

let rec print_local_declarations ch xs =
  let print_cpp fmt  = fprintf ch fmt in
  let rec helper ?(first=true) xs =
    match xs with
      | [] -> ()
      | a::b::c::d::e::tail ->
          print_cpp "  CAML%slocal5(%s);\n" (if first then "" else "x")
            (String.concat ~sep:"," [a;b;c;d;e]);
          helper ~first:false tail
      | tail ->
          print_cpp "  CAML%slocal%d(%s);\n" (if first then "" else "x")
            (List.length tail) (String.concat ~sep:"," tail);
  in
  helper xs

exception VaribleStackEmpty
let gen_signal_stub ~classname ~signal ~typ ch fn_name =
  (* classname --- name of class where signal is *)
  (* signal is name of signal in classname *)
  (* ~typ --- argumentof signal. It is alone because properties' notifiers has 1 argument *)
  (* fn_name is C++ stub function name. It will be used while generating OCaml code *)
  (* ch --- is channel where we'll put code *)

  let locals_count = TypAst.aux_variables_count typ in
  let locals = List.init ~f:(fun n -> sprintf "_z%d" n) locals_count in
  print_local_declarations ch locals;
  let (get_var, release_var) = 
    let stack = ref locals  in (* tail because we need not _ans *)
    let get_var () = match !stack with 
      | x::xs -> 
          stack:= xs;
          x
      | [] -> raise VaribleStackEmpty
    in
    let release_var name = Ref.replace stack (fun xs -> name::xs) in
    (get_var,release_var)
  in  
  let new_cpp_var =
    let count = ref 0 in
    fun () -> incr count; sprintf "x%d" !count
  in
  (* NB. All signals return void *)
  fprintf ch "extern \"C\" value %s(value _obj, value _arg) {\n" fn_name;
  fprintf ch "  CAMLparam2(_obj,_arg);\n";
  fprintf ch "  %s *cppobj = (%s*)_obj;\n" classname classname;
  fprintf ch "  %s arg;\n" (TypAst.to_cpp_type typ);
  cpp_value_of_ocaml  ch (get_var,release_var,new_cpp_var) ~cpp_var:"arg" ~ocaml_var:"_arg" typ;
  fprintf ch "  cppobj->emit_%s(arg);\n" signal;
  fprintf ch "  CAMLreturn(Val_unit);\n";
  fprintf ch "}\n\n"



(* Generates code of C++ method which calls specific OCaml registred value *)
let gen_meth ~classname ~ocaml_methname ?(options=[])
    file_h file_cpp ((name,args,res) as slot) = 
  let (_ : Yaml2.Types.typ list) = args in
  let (_ : Yaml2.Types.typ) = res in
  printf "Generatig meth '%s'\n" name;
  let print_h   fmt = fprintf file_h   fmt in
  let print_cpp fmt = fprintf file_cpp fmt in
  print_cpp "// %s\n" (List.map (args@[res]) ~f:TypAst.to_ocaml_type |> String.concat ~sep:" -> ");
  let args = if args = [`Unit] then [] else args in
  let argnames = List.mapi args ~f: (fun i _ -> "x" ^ string_of_int i) in
  let lst = List.map args ~f:(TypAst.to_cpp_type) in
  let arg' = List.map2_exn lst argnames ~f:(sprintf "%s %s") in
  let () = 
    print_h  "  %s%s %s(%s);\n"
    (if List.mem options `Invokable then "Q_INVOKABLE " else "") (TypAst.to_cpp_type res)
    name (String.concat ~sep:"," arg') in
  let () = 
    print_cpp "%s %s::%s(%s) {\n" (TypAst.to_cpp_type res) classname
    name (String.concat ~sep:"," arg') in
  print_cpp "  CAMLparam0();\n";
  let locals_count = 1 + (* for _ans *)
    List.fold_left ~f:(fun acc x -> max acc (TypAst.aux_variables_count x)) ~init:0 (res::args) in
  let locals = 
    if locals_count = 1
    then ["_ans"]
    else "_ans" :: (List.init ~f:(fun n -> sprintf "_qq%d" n) (locals_count -1) )
  in
  assert (List.length locals = locals_count);
  print_local_declarations file_cpp locals;

  let ocaml_closure = ocaml_methname slot in
  (* TODO: use caml_callback, caml_callback2, caml_callback3 to speedup *)
  print_cpp "  value *closure = caml_named_value(\"%s\");\n" ocaml_closure;
  print_cpp "  Q_ASSERT_X(closure!=NULL, \"%s::%s\",\n"      classname name;
  print_cpp "             \"ocaml's closure `%s` not found\");\n"   ocaml_closure;
  
  (* Now we will generate OCaml values for arguments *)
  (*  We will look at argument type and call recursive function for generating *)
  (* It will use free aux variables. We need a stack to save them*)
  let (get_var, release_var) = 
    let stack = ref (List.tl_exn locals)  in (* tail because we need not _ans *)
    let get_var () = match !stack with 
      | x::xs -> 
          stack:= xs;
          x
      | [] -> raise VaribleStackEmpty
    in
    let release_var name = Ref.replace stack (fun xs -> name::xs) in
    (get_var,release_var)
  in
  
  
  let n = List.length argnames in

  let call_closure_str = match n with 
    | 0 -> "caml_callback(*closure, Val_unit)"
    | _ -> begin
      (* Generating arguments for calling *)
      print_cpp "  value *args = new value[%d];\n" n;
      List.iter2i args argnames ~f:(fun i arg cppvar ->
        ocaml_value_of_cpp file_cpp (get_var,release_var)
          ~tab:1 ~ocamlvar:(sprintf "args[%d]" i) ~cppvar arg
      );
      print_cpp "  // delete args or not?\n";
      sprintf "caml_callbackN(*closure, %d, args)" n
    end
  in
  let (hasSetter,res) = 
    match res with 
      | `Unit  ->  begin
        match List.find options ~f:(function `Setter _ -> true | _ -> false) with
          | Some (`Setter signal) ->
              print_cpp "  _ans = %s;\n" call_closure_str;
              (Some signal, `Bool)
          | None ->
              print_cpp "  %s;\n" call_closure_str;
              (None,res)
          | _ -> assert false
      end
      | _      ->  
          print_cpp "  _ans = %s;\n" call_closure_str;
          (None,res)
  in
  (* Now we should convert OCaml result value to C++*)
  let new_cpp_var =
    let last_index = ref 0 in
    let f () = 
      incr last_index;
      sprintf "xx%d" !last_index
    in
    f
  in
  let () = 
    match res with
      | `Unit  -> 
          assert (hasSetter = None);
          ()
      | _ -> begin
          let cpp_ans_var = "cppans" in
          print_cpp "  %s %s;\n" (TypAst.to_cpp_type res) cpp_ans_var;
          cpp_value_of_ocaml file_cpp (get_var,release_var, new_cpp_var) cpp_ans_var "_ans" res;
          match hasSetter with
            | Some signal ->
                assert (res = `Bool);
                print_cpp "  if (cppans) emit %s(%s);\n" signal (List.hd_exn argnames)
            | None  -> 
                print_cpp "  return %s;\n" cpp_ans_var
      end
  in
  print_cpp "}\n";
  flush file_cpp


let name_for_slot (name,args,res) = 
  let rec typ_to_ocaml_string = function
    | `Unit  -> "unit"
    | `Int  -> "int"
    | `String   -> "string"
    | `Bool   -> "bool"
    | `Float  -> "float"
    | `Tuple xs ->
        String.concat ~sep:"_star_" (List.map ~f:typ_to_ocaml_string xs)
    | `List t -> sprintf "%s_list" (typ_to_ocaml_string t)
  in
  let conv = typ_to_ocaml_string in
  String.concat ~sep:"_" (ocaml_classname :: name :: (conv res) :: (List.map ~f:conv args) )


let gen_cpp {classname; members; slots; props; _ } =
  let big_name = String.capitalize classname ^ "_H" in
  let h_file = open_out (classname ^ ".h") in
  let print_h fmt = fprintf h_file fmt in
  let cpp_file = open_out (classname ^ ".cpp") in
  let print_cpp fmt = fprintf cpp_file fmt in
  let print_time ch = 
    fprintf ch "// Generated at %s\n" Time.(now () |> to_string)
  in
  print_time cpp_file;
  print_time h_file;
  print_h "#ifndef %s\n" big_name;
  print_h "#define %s\n\n" big_name;
  print_h "#include <QtCore/QObject>\n";
  print_h "#include <QtCore/QDebug>\n";
  print_h "#include \"kamlo.h\"\n\n";
  print_h "class %s : public QObject\n{\n" classname;
  print_h "  Q_OBJECT\n";
  print_h "public:\n";

  print_cpp "#include \"%s.h\"\n\n" classname;

  (* properties *)
  List.iter props ~f:(fun ({name;getter;setter;notifier;typ} as prop) ->
    print_h "public:\n";
    print_h "  Q_PROPERTY(%s %s %s READ %s NOTIFY %s)\n" 
      (TypAst.to_cpp_type typ) name (match setter with Some x -> "WRITE "^x | None -> "") getter notifier;
    let ocaml_methname (x,y,_) = ocaml_name_of_prop ~classname `Getter prop in
    gen_meth ~classname ~ocaml_methname ~options:[] h_file cpp_file (getter,[`Unit],typ);
    let () = 
      match setter with
        | Some setter ->
            let ocaml_methname (x,y,_) = ocaml_name_of_prop ~classname `Setter prop in
            gen_meth ~classname ~ocaml_methname 
              ~options:[`Setter notifier] h_file cpp_file (setter,[typ],`Unit);
        | None -> ()
    in
    print_h "signals:\n";
    print_h "  void %s(%s);\n" notifier (TypAst.to_cpp_type typ);
    gen_signal_stub ~classname ~signal:notifier ~typ cpp_file (sprintf "stub_%s_emit_%s" name notifier);
    print_h "public:\n";
    print_h "  void emit_%s(%s arg1) {\n" notifier (TypAst.to_cpp_type typ);
    print_h "    emit %s(arg1);\n" notifier;
    print_h "  }\n\n"
  );
  print_h "public:\n";
  print_h "  explicit %s(QObject *parent = 0) : QObject(parent) {}\n" classname;
  List.iter members ~f:(gen_meth ~classname ~options:[`Invokable]
                          ~ocaml_methname:name_for_slot h_file cpp_file);
  if slots <> [] then (
    print_h "public slots:\n";
    List.iter slots ~f:(gen_meth ~classname ~options:[] ~ocaml_methname:name_for_slot h_file cpp_file)
  );
  print_h "};\n";
  print_h "#endif\n\n";
  Out_channel.close h_file;
  Out_channel.close cpp_file







