(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Utils_js

exception Found of string

let find documentation = raise (Found documentation)

let find_description comments =
  Base.Option.iter (Jsdoc.of_comments comments) ~f:(Jsdoc.description %> find)

class documentation_searcher (def_loc : Loc.t) =
  object (this)
    inherit [unit, Loc.t] Flow_ast_visitor.visitor ~init:() as super

    method is_target loc = Loc.equal def_loc loc

    method! variable_declaration stmt_loc decl =
      let open Flow_ast.Statement.VariableDeclaration in
      let { declarations; comments; _ } = decl in
      Base.List.iter declarations ~f:(function
          | ( _,
              Declarator.
                { id = (_, Flow_ast.Pattern.(Identifier Identifier.{ name = (loc, _); _ })); _ } )
            when this#is_target loc ->
            find_description comments
          | (_, Declarator.{ init = Some (loc, _); _ }) when this#is_target loc ->
            find_description comments
          | _ -> ());
      super#variable_declaration stmt_loc decl

    method! class_ stmt_loc cls =
      let open Flow_ast.Class in
      let { id; comments; _ } = cls in
      Base.Option.iter id ~f:(fun (loc, _) -> if this#is_target loc then find_description comments);
      super#class_ stmt_loc cls

    method! function_ loc func =
      let open Flow_ast.Function in
      let { comments; _ } = func in
      if this#is_target loc then find_description comments;
      super#function_ loc func

    method! declare_variable stmt_loc decl =
      let open Flow_ast.Statement.DeclareVariable in
      let { id = (loc, _); comments; _ } = decl in
      if this#is_target loc then find_description comments;
      super#declare_variable stmt_loc decl

    method! declare_class stmt_loc decl =
      let open Flow_ast.Statement.DeclareClass in
      let { id = (loc, _); comments; _ } = decl in
      if this#is_target loc then find_description comments;
      super#declare_class stmt_loc decl

    method! declare_function stmt_loc decl =
      let open Flow_ast.Statement.DeclareFunction in
      let { id = (loc, _); comments; _ } = decl in
      if this#is_target loc then find_description comments;
      super#declare_function stmt_loc decl
  end

let documentation_of_def_loc def_loc typed_ast =
  let searcher = new documentation_searcher def_loc in
  try
    ignore (searcher#program typed_ast);
    None
  with Found documentation -> Some documentation

let of_getdef_loc ~reader def_loc =
  let open Base.Option in
  Loc.source def_loc >>= Parsing_heaps.Reader.get_ast ~reader >>= documentation_of_def_loc def_loc
