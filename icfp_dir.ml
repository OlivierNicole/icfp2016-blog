(* Build a Git skeleton of ICFP blogs from the issues *)

open Lwt
open Cmdliner
open Printf
open Astring

module T = Github_t

let findl all issue labels =
   List.fold_left (fun a day ->
     match a with
     | Some a -> Some a
     | None -> 
        try Some (List.find (fun d -> day = d.T.label_name) labels)
        with Not_found -> None) None all |>
   function
   | Some r -> r.T.label_name
   | None -> failwith (Printf.sprintf "None of [%s] found in issue %d"
               (String.concat ~sep:"," all) issue.T.issue_number)
 
let day_of_labels =
  [ "Sunday 18th"; "Monday 19th"; "Tuesday 20th"; "Wednesday 21st";
    "Thursday 22nd"; "Friday 23rd"; "Saturday 24th" ] |> findl

let ampm_of_labels = ["AM";"PM"] |> findl

let events = 
   ["HOPE";"CUFP";"Erlang";"FARM";"FHPC";"Haskell";"HIW";
    "ICFP";"ML";"OCaml";"PLMW";"Scheme";"TyDe";
    "Tutorial T1"; "Tutorial T2"; "Tutorial T3";"Tutorial T4";
    "Tutorial T5";"Tutorial T6";"Tutorial T7";"Tutorial T8"]

let is_tutorial l =
  String.with_range ~len:10 l = "Tutorial T"

let event_of_labels = findl events

let parse_title issue t =
   match String.cut ~sep:": " t with
   |Some (time,title) -> time, title
   |None -> failwith (Printf.sprintf "bad title in issue %d" issue.T.issue_number)

let all_issues = ref []
let write_file fname b =
  let fout = open_out fname in
  output_string fout b;
  close_out fout;
  print_endline ("Wrote " ^ fname)

let title_dir title =
  String.with_range ~first:0 ~len:20 title |>
  String.Ascii.lowercase |>
  String.map (function |' '|':' -> '-' |x -> x)
 
let generate_page user repo issue =
  all_issues := issue :: !all_issues;
  let issue_labels = issue.T.issue_labels in
  let day = day_of_labels issue issue_labels in
  let ampm = ampm_of_labels issue issue_labels in
  let event = event_of_labels issue issue_labels in
  if not (is_tutorial event) then begin
  let time,title = parse_title issue issue.T.issue_title in
  let basedir = "./repo" in
  let fname = Printf.sprintf "%s/%s/%s" basedir event (title_dir title) in
  ignore (Sys.command (Printf.sprintf "mkdir -p %S" fname));
  let tmpl = Printf.sprintf
"---
title: %s
author: whoami (Anonymous)
abstract: %s
---

This is the template for you to liveblog about the talk,
which is at %s on %s %s %s.  Just replace the content here
with your edits, and then submit it online.
" title title event day time ampm in
  let fname = fname ^ "/template.md" in
  write_file fname tmpl;
  let fname = Printf.sprintf "%s/%s/%s.md" basedir event (title_dir title) in
  let tmpl = Printf.sprintf
"---
title: %s
author: whoami (TODO)
abstract: Notes on %s
---

This is the liveblog notes.  In case there are multiple
people liveblogging, you can temporarily edit your notes
at %s url and then copy them into this one in one
commit.
" title title
  (Printf.sprintf "[%s](%s/template.md)" "this" (title_dir title))
  in
  write_file fname tmpl;
  end

let generate_indexes () =
  let basedir = "./repo" in
  let tmpl = Printf.sprintf 
"---
title: ICFP 2016 Events
author: Gemma Gordon, Anil Madhavapeddy
abstract: All the liveblogs
---


%s

Some useful resources:
* <https://github.com/gasche/icfp2016-papers>
* <http://icfpconference.org>
" (String.concat ~sep:"\n"
    (List.map (fun e -> Printf.sprintf "* [%s](%s) " e e)
    (List.filter (fun e -> not (is_tutorial e)) events))) in
  write_file (basedir ^ "/Index") tmpl;
  (* event indexes *)
  List.iter (fun event ->
    let fname = Printf.sprintf "%s/%s/Index" basedir event in
    let articles =
      List.filter (fun i -> event_of_labels i i.T.issue_labels = event) !all_issues |> fun is ->
      String.concat ~sep:"\n" (List.map (fun i ->
        let time, title = parse_title i i.T.issue_title in
        Printf.sprintf "* %s: [%s](%s)" time title (title_dir title)) is)
    in
    let tmpl = Printf.sprintf
"---
title: %s
author: Gemma Gordon, Anil Madhavapeddy, Gabriel Scherer
abstract: Event is %s
---

%s
" event event articles in
    write_file fname tmpl
  ) (List.filter (fun e -> not (is_tutorial e)) events)

let get_user_repos =
  List.map (fun r ->
    match Stringext.split ~max:2 ~on:'/' r with
    | [user;repo] -> (user,repo)
    | _ -> eprintf "Repositories must be in username/repo format"; exit 1
  ) 

let print_issue token repos =
  (* Get the issues per repo *)
  get_user_repos repos |>
  Lwt_list.iter_s (fun (user,repo) ->
    Github.(Monad.(run (
      Issue.for_repo ~token ~user ~repo () |>
      Stream.to_list >|= 
      List.iter (generate_page user repo)
    )))
  ) >|=
  generate_indexes

let cmd =
  let cookie = Jar_cli.cookie () in
  let repos = Jar_cli.repos ~doc_append:" to list issues and PRs" () in

  let doc = "generate ICFP program" in
  let man = [
    `S "BUGS";
    `P "Email bug reports to <anil@recoil.rog>";
  ] in
  Term.((pure (fun t r ->
    Lwt_main.run (print_issue t r)
  ) $ cookie $ repos)),
  Term.info "git-list-issues" ~version:"1.0.0" ~doc ~man

let () = Fmt_tty.setup_std_outputs ()

let () = match Term.eval cmd with `Error _ -> exit 1 | _ -> exit 0

(*
 * Copyright (c) 2015 David Sheets <sheets@alum.mit.edu>
 * Copyright (c) 2015-2016 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)


