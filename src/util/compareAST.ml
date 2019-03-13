open Cil

let name_of_global glob =
  match glob with
  | GFun (fundec, l) -> fundec.svar.vname
  | GVar (var, init, l) -> var.vname
  | GVarDecl (var, l) -> var.vname
  | _ -> raise (Failure "No variable or function") 


module StringMap = Map.Make(String)

let eq_list eq xs ys = 
    try
        List.for_all (fun (a,b) -> eq a b) (List.combine xs ys)
    with Invalid_argument _ -> false

let eqB (a: Cil.block) (b: Cil.block) =
    a.Cil.battrs = b.Cil.battrs && a.bstmts = b.bstmts

let eqS (a: Cil.stmt) (b: Cil.stmt) =
  a.Cil.skind = b.Cil.skind

let print (a: Pretty.doc)  =
    print_endline @@ Pretty.sprint 100 a

let rec eq_constant (a: constant) (b: constant) = match a, b with
    CInt64 (val1, kind1, str1), CInt64 (val2, kind2, str2) -> val1 = val2 && kind1 = kind2 (* Ignore string representation, i.e. 0x2 == 2 *)
    | CEnum (exp1, str1, enuminfo1), CEnum (exp2, str2, enuminfo2) -> eq_exp exp1 exp2 (* Ignore name and enuminfo  *)
    | a, b -> a = b

and eq_exp (a: exp) (b: exp) = match a,b with
    | Const c1, Const c2 -> eq_constant c1 c2
    | Lval lv1, Lval lv2 -> eq_lval lv1 lv2
    | SizeOf typ1, SizeOf typ2 -> eq_typ typ1 typ2
    | SizeOfE exp1, SizeOfE exp2 -> eq_exp exp1 exp2
    | SizeOfStr str1, SizeOfStr str2 -> str1 = str2 (* possibly, having the same length would suffice *)
    | AlignOf typ1, AlignOf typ2 -> eq_typ typ1 typ2 
    | AlignOfE exp1, AlignOfE exp2 -> eq_exp exp1 exp2
    | UnOp (op1, exp1, typ1), UnOp (op2, exp2, typ2) -> op1 == op2 && eq_exp exp1 exp2 && eq_typ typ1 typ2
    | BinOp (op1, left1, right1, typ1), BinOp (op2, left2, right2, typ2) ->  op1 = op2 && eq_exp left1 left2 && eq_exp right1 right2 && eq_typ typ1 typ2
    | CastE (typ1, exp1), CastE (typ2, exp2) -> eq_typ typ1 typ2 &&  eq_exp exp1 exp2 
    | AddrOf lv1, AddrOf lv2 -> eq_lval lv1 lv2 
    | StartOf lv1, StartOf lv2 -> eq_lval lv1 lv2
    | _, _ -> false

and eq_lhost (a: lhost) (b: lhost) = match a, b with 
    Var v1, Var v2 -> eq_varinfo v1 v2 
    | Mem exp1, Mem exp2 -> eq_exp exp1 exp2 
    | _, _ -> false

and eq_typinfo (a: typeinfo) (b: typeinfo) = a.tname = b.tname && eq_typ a.ttype b.ttype (* Ignore the treferenced field *)

and eq_typ_acc (a: typ) (b: typ) (acc: (typ * typ) list) = 
  if( List.exists (fun x-> match x with (x,y)-> a==x && b == y) acc) 
    then true 
    else (let acc = List.cons (a,b) acc in
          match a, b with
          | TPtr (typ1, attr1), TPtr (typ2, attr2) -> eq_typ_acc typ1 typ2 acc && eq_list eq_attribute attr1 attr2
          | TArray (typ1, (Some lenExp1), attr1), TArray (typ2, (Some lenExp2), attr2) -> eq_typ_acc typ1 typ2 acc && eq_exp lenExp1 lenExp2 &&  eq_list eq_attribute attr1 attr2
          | TArray (typ1, None, attr1), TArray (typ2, None, attr2) -> eq_typ_acc typ1 typ2 acc && eq_list eq_attribute attr1 attr2
          | TFun (typ1, (Some list1), varArg1, attr1), TFun (typ2, (Some list2), varArg2, attr2) 
                      ->  eq_typ_acc typ1 typ2 acc && eq_list eq_args list1 list2 && varArg1 = varArg2 &&
                          eq_list eq_attribute attr1 attr2
          | TFun (typ1, None, varArg1, attr1), TFun (typ2, None, varArg2, attr2) 
                      ->  eq_typ_acc typ1 typ2 acc && varArg1 = varArg2 &&
                          eq_list eq_attribute attr1 attr2
          | TNamed (typinfo1, attr1), TNamed (typeinfo2, attr2) -> eq_typinfo typinfo1 typeinfo2 && eq_list eq_attribute attr1 attr2
          | TComp (compinfo1, attr1), TComp (compinfo2, attr2) ->  eq_compinfo compinfo1 compinfo2 acc &&  eq_list eq_attribute attr1 attr2 
          | TEnum (enuminfo1, attr1), TEnum (enuminfo2, attr2) -> eq_enuminfo enuminfo1 enuminfo2 && eq_list eq_attribute attr1 attr2
          | TBuiltin_va_list attr1, TBuiltin_va_list attr2 -> eq_list eq_attribute attr1 attr2
          | _, _ -> a = b)

and eq_typ (a: typ) (b: typ) = 
  (* We compare the typsigs: so TNameds, i.e. typedefs, are unrolled *)
  let a' = typeSig a in
  let b' = typeSig b in
  eq_typsig a' b'
 
and eq_eitems (a: string * exp * location) (b: string * exp * location) = match a, b with
  (name1, exp1, _l1), (name2, exp2, _l2) -> name1 = name2 && eq_exp exp1 exp2
  (* Ignore location *)

and eq_enuminfo (a: enuminfo) (b: enuminfo) = a.ename = b.ename && eq_list eq_attribute a.eattr b.eattr &&
  eq_list eq_eitems a.eitems b.eitems
  (* Ignore ereferenced *)

and eq_args (a: string * typ * attributes) (b: string * typ * attributes) = match a, b with
  (name1, typ1, attr1), (name2, typ2, attr2) -> name1 = name2 && eq_typ typ1 typ2 && eq_list eq_attribute attr1 attr2

and eq_typsig (a: typsig) (b: typsig) = 
  match a, b with
  | TSArray (ts1, i1, attr1), TSArray (ts2, i2, attr2) -> eq_typsig ts1 ts2 && i1 = i2 && eq_list eq_attribute attr1 attr2
  | TSPtr (ts1, attr1), TSPtr (ts2, attr2) -> eq_typsig ts1 ts2 && eq_list eq_attribute attr1 attr2
  | TSComp (b1, str1, attr1), TSComp (b2, str2, attr2) -> b1 = b2 && str1 = str2 && eq_list eq_attribute attr1 attr2
  | TSFun (ts1, Some tsList1, b1, attr1), TSFun (ts2, Some tsList2, b2, attr2) -> eq_typsig ts1 ts2 && eq_list eq_typsig tsList1 tsList2 && b1 = b2 && eq_list eq_attribute attr1 attr2
  | TSFun (ts1, None, b1, attr1), TSFun (ts2, None, b2, attr2) -> eq_typsig ts1 ts2 && b1 = b2 && eq_list eq_attribute attr1 attr2
  | TSEnum (str1, attr1), TSEnum (str2, attr2) -> str1 = str2 && eq_list eq_attribute attr1 attr2
  | TSBase typ1, TSBase typ2 -> eq_typ_acc typ1 typ2 []
  | _, _ -> false

and eq_attrparam (a: attrparam) (b: attrparam) = match a, b with
  | ACons (str1, attrparams1), ACons (str2, attrparams2) -> str1 = str2 && eq_list eq_attrparam attrparams1 attrparams2
  | ASizeOf typ1, ASizeOf typ2 -> eq_typ typ1 typ2
  | ASizeOfE attrparam1, ASizeOfE attrparam2 -> eq_attrparam attrparam1 attrparam2
  | ASizeOfS typsig1, ASizeOfS typsig2 -> eq_typsig typsig1 typsig2
  | AAlignOf typ1, AAlignOf typ2 -> eq_typ typ1 typ2
  | AAlignOfE attrparam1, AAlignOfE attrparam2 -> eq_attrparam attrparam1 attrparam2
  | AAlignOfS typsig1, AAlignOfS typsig2 -> eq_typsig typsig1 typsig2
  | AUnOp (op1, attrparam1), AUnOp (op2, attrparam2) -> op1 = op2 && eq_attrparam attrparam1 attrparam2
  | ABinOp (op1, left1, right1), ABinOp (op2, left2, right2) -> op1 = op2 && eq_attrparam left1 left2 && eq_attrparam right1 right2
  | ADot (attrparam1, str1), ADot (attrparam2, str2) -> eq_attrparam attrparam1 attrparam2 && str1 = str2
  | AStar attrparam1, AStar attrparam2 -> eq_attrparam attrparam1 attrparam2 
  | AAddrOf attrparam1, AAddrOf attrparam2 -> eq_attrparam attrparam1 attrparam2
  | AIndex (left1, right1), AIndex (left2, right2) -> eq_attrparam left1 left2 && eq_attrparam right1 right2
  | AQuestion (left1, middle1, right1), AQuestion (left2, middle2, right2) -> eq_attrparam left1 left2 && eq_attrparam middle1 middle2 && eq_attrparam right1 right2
  | a, b -> a = b

and eq_attribute (a: attribute) (b: attribute) = match a, b with
  Attr (name1, params1), Attr (name2, params2) -> name1 = name2 && eq_list eq_attrparam params1 params2

and eq_varinfo (a: varinfo) (b: varinfo) = a.vname = b.vname && eq_typ a.vtype b.vtype && eq_list eq_attribute a.vattr b.vattr &&
  a.vstorage = b.vstorage && a.vglob = b.vglob && a.vinline = b.vinline && a.vaddrof = b.vaddrof
  (* Ignore the location, vid, vreferenced, vdescr, vdescrpure *)

(* Accumulator is needed because of recursive types: we have to assume that two types we already encountered in a previous step of the recursion are equivalent *)
 and eq_compinfo (a: compinfo) (b: compinfo) (acc: (typ * typ) list) = a.cstruct = b.cstruct && a.cname = b.cname && eq_list (fun a b-> eq_fieldinfo a b acc) a.cfields b.cfields 
  && eq_list eq_attribute a.cattr b.cattr && a.cdefined = b.cdefined (* Ignore ckey, and ignore creferenced *)

and eq_fieldinfo (a: fieldinfo) (b: fieldinfo) (acc: (typ * typ) list)=
    a.fname = b.fname && eq_typ_acc a.ftype b.ftype acc && a.fbitfield = b.fbitfield &&  eq_list eq_attribute a.fattr b.fattr

and eq_offset (a: offset) (b: offset) = match a, b with
    NoOffset, NoOffset -> true 
    | Field (info1, offset1), Field (info2, offset2) -> eq_fieldinfo info1 info2 [] && eq_offset offset1 offset2 
    | Index (exp1, offset1), Index (exp2, offset2) -> eq_exp exp1 exp2 && eq_offset offset1 offset2
    | _, _ -> false 

and eq_lval (a: lval) (b: lval) = match a, b with
    (host1, off1), (host2, off2) -> eq_lhost host1 host2 && eq_offset off1 off2  

let eq_instr (a: instr) (b: instr) = match a, b with
    | Set (lv1, exp1, _l1), Set (lv2, exp2, _l2) -> eq_lval lv1 lv2 && eq_exp exp1 exp2
    | Call (Some lv1, f1, args1, _l1), Call (Some lv2, f2, args2, _l2) -> eq_lval lv1 lv2 && eq_exp f1 f2 && eq_list eq_exp args1 args2
    | Call (None, f1, args1, _l1), Call (None, f2, args2, _l2) -> eq_exp f1 f2 && eq_list eq_exp args1 args2
    | Asm _, Asm _ -> false (* We don't handle inline assembler yet *)
    | _, _ -> false

let eq_label (a: label) (b: label) = match a, b with
    Label (lb1, _l1, s1), Label (lb2, _l2, s2) -> lb1 = lb2 && s1 = s2 
|   Case (exp1, _l1), Case (exp2, _l2) -> exp1 = exp2 
| Default _l1, Default l2 -> true
| _, _ -> false

(* This is needed for checking whether a goto does go to the same semantic location/statement*)
let eq_stmt_with_location ((a, af): stmt * fundec) ((b, bf): stmt * fundec) =
  let offsetA = a.sid - (List.hd af.sallstmts).sid in
  let offsetB = b.sid - (List.hd bf.sallstmts).sid in
  eq_list eq_label a.labels b.labels && offsetA = offsetB

let rec eq_stmtkind ((a, af): stmtkind * fundec) ((b, bf): stmtkind * fundec) =
  let eq_block' = fun x y -> eq_block (x, af) (y, bf) in
  match a, b with
    | Instr is1, Instr is2 -> eq_list eq_instr is1 is2
    | Return (Some exp1, _l1), Return (Some exp2, _l2) -> eq_exp exp1 exp2
    | Return (None, _l1), Return (None, _l2) -> true
    | Return _, Return _ -> false
    | Goto (st1, _l1), Goto (st2, _l2) -> eq_stmt_with_location (!st1, af) (!st2, bf)
    | Break _, Break _ -> true
    | Continue _, Continue _ -> true
    | If (exp1, then1, else1, _l1), If (exp2, then2, else2, _l2) -> eq_exp exp1 exp2 && eq_block' then1 then2 && eq_block' else1 else2
    | Switch (exp1, block1, stmts1, _l1), Switch (exp2, block2, stmts2, _l2) -> eq_exp exp1 exp2 && eq_block' block1 block2 && eq_list (fun a b -> eq_stmt (a,af) (b,bf)) stmts1 stmts2
    | Loop (block1, _l1, _con1, _br1), Loop (block2, _l2, _con2, _br2) -> eq_block' block1 block2
    | Block block1, Block block2 -> eq_block' block1 block2
    | TryFinally (tryBlock1, finallyBlock1, _l1), TryFinally (tryBlock2, finallyBlock2, _l2) -> eq_block' tryBlock1 tryBlock2 && eq_block' finallyBlock1 finallyBlock2
    | TryExcept (tryBlock1, exn1, exceptBlock1, _l1), TryExcept (tryBlock2, exn2, exceptBlock2, _l2) -> eq_block' tryBlock1 tryBlock2 && eq_block' exceptBlock1 exceptBlock2
    | _, _ -> false

and eq_stmt ((a, af): stmt * fundec) ((b, bf): stmt * fundec) =
    List.for_all (fun (x,y) -> eq_label x y) (List.combine a.labels b.labels) &&
    eq_stmtkind (a.skind, af) (b.skind, bf)

and eq_block ((a, af): Cil.block * fundec) ((b, bf): Cil.block * fundec) =
    a.battrs = b.battrs && List.for_all (fun (x,y) -> eq_stmt (x, af) (y, bf)) (List.combine a.bstmts b.bstmts)

let eqF (a: Cil.fundec) (b: Cil.fundec) =
    try
       eq_varinfo a.svar b.svar && 
       List.for_all (fun (x, y) -> eq_varinfo x y) (List.combine a.sformals b.sformals) && 
       List.for_all (fun (x, y) -> eq_varinfo x y) (List.combine a.slocals b.slocals) &&
       eq_block (a.sbody, a) (b.sbody, b)
    with Invalid_argument _ -> (* One of the combines failed because the lists have differend length *)
                            false
       (*&& a.sformals == b.sformals &&
       a.slocals == b.slocals && eqB a.sbody b.sbody && 
       List.for_all (fun (a,b) -> eqS a b) (List.combine a.sallstmts b.sallstmts)*)

let eq_glob (a: global) (b: global) = match a, b with
  | GFun (f,_), GFun (g,_) -> eqF f g
  | GVar (x, _, _), GVar (y,_, _) -> eq_varinfo x y
  | GVarDecl (x, _), GVarDecl (y, _) -> eq_varinfo x y
  | _ -> false

(* Returns a list of changed functions *)
let compareCilFiles (oldAST: Cil.file) (newAST: Cil.file) =
  let string_of_glob (glob: global) = match glob with
    | GFun (v, l) ->  "fun" ^ (string_of_int v.svar.vid)
    | _ -> raise (Failure "No Function")
  in
  let oldMap = StringMap.empty in
  let addGlobal map global  = 
    try
      StringMap.add (name_of_global global) global map
    with
      e -> map
  in
  let checkUnchanged map global = 
    try 
      let name = name_of_global global in
      (try
        let oldFunction =  StringMap.find name map in
        (* Do a (recursive) equal comparision ignoring location information *)
        let identical = eq_glob oldFunction global in
        print_endline (name ^ " " ^ string_of_bool identical);
        Some (identical, global, if not identical then Some oldFunction else None)
      with Not_found -> Some (false, global, None);)
    with e -> None (* Global was no variable or function, it does not belong into the map *)
  in
  (* Store a map from functionNames in the old file to the function definition*)
  let oldMap = Cil.foldGlobals oldAST addGlobal oldMap in
  (*  For each function in the new file, check whether a function with the same name 
      already existed in the old version, and whether it is the same function. *)
  Cil.foldGlobals newAST
    (fun acc glob -> match checkUnchanged oldMap glob with
      | Some (false, fundec, None) -> (List.cons fundec (fst acc), snd acc)
      | Some (false, fundec, (Some old)) -> (List.cons fundec (fst acc), List.cons (string_of_glob old) (snd acc))
      | _ -> acc) ([], [])