///|
/// Schema lint 的问题级别。Error 表示 Schema 元数据缺少关键安全约束，
/// Warning 表示协议形状可工作，但会降低静态分析能力或扩大误用风险。
pub(all) enum LintSeverity {
  LintWarning
  LintError
} derive(Eq, Debug, ToJson)

///|
pub extend LintSeverity with Eq::{not_equal, equal}

///|
pub extend LintSeverity with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LintSeverity with ToJson::{to_json}

///|
pub fn LintSeverity::name(self : LintSeverity) -> String {
  match self {
    LintWarning => "warning"
    LintError => "error"
  }
}

///|
/// Schema linter 产生的稳定、机器可读问题。
pub(all) struct LintIssue {
  code : String
  severity : LintSeverity
  path : String
  message : String
} derive(Eq, Debug, ToJson)

///|
pub extend LintIssue with Eq::{not_equal, equal}

///|
pub extend LintIssue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LintIssue with ToJson::{to_json}

///|
pub fn LintIssue::render(self : LintIssue) -> String {
  "[\{self.severity.name()}] \{self.code} at \{self.path}: \{self.message}"
}

///|
fn lint_string_starts_with(value : String, prefix : String) -> Bool {
  if value.length() < prefix.length() {
    return false
  }
  for index in 0..<prefix.length() {
    if value.code_unit_at(index) != prefix.code_unit_at(index) {
      return false
    }
  }
  true
}

///|
fn schema_has_constraint(node : SchemaNode, prefix : String) -> Bool {
  for constraint in node.constraints {
    if lint_string_starts_with(constraint, prefix) {
      return true
    }
  }
  false
}

///|
fn lint_issue(
  issues : Array[LintIssue],
  code : String,
  severity : LintSeverity,
  path : String,
  message : String,
) -> Unit {
  issues.push({ code, severity, path, message, })
}

///|
fn child_path(parent : String, child : SchemaNode, index : Int) -> String {
  let segment = if child.name == "" { "#\{index}" } else { child.name }
  if parent == "" {
    segment
  } else {
    parent + "." + segment
  }
}

///|
fn lint_duplicate_child_names(
  node : SchemaNode,
  path : String,
  issues : Array[LintIssue],
) -> Unit {
  for left = 0; left < node.children.length(); left = left + 1 {
    let name = node.children[left].name
    if name != "" {
      for right = left + 1; right < node.children.length(); right = right + 1 {
        if node.children[right].name == name {
          lint_issue(
            issues,
            "duplicate-child-name",
            LintWarning,
            path,
            "multiple child fields share the name '" +
            name +
            "', which makes traces and generated tooling ambiguous",
          )
          break
        }
      }
    }
  }
}

///|
fn lint_node(
  node : SchemaNode,
  path : String,
  issues : Array[LintIssue],
) -> Unit {
  lint_duplicate_child_names(node, path, issues)
  match node.kind {
    "length-prefixed" =>
      if !schema_has_constraint(node, "max_length=") {
        lint_issue(
          issues,
          "missing-max-length",
          LintError,
          path,
          "length-prefixed fields should declare max_length so tooling can prove a local allocation bound",
        )
      }
    "count-prefixed-array" =>
      if !schema_has_constraint(node, "max_count=") {
        lint_issue(
          issues,
          "missing-max-count",
          LintError,
          path,
          "count-prefixed arrays should declare max_count so tooling can prove a local collection bound",
        )
      }
    "bounded" =>
      if !schema_has_constraint(node, "length=") {
        lint_issue(
          issues,
          "missing-bounded-length",
          LintError,
          path,
          "bounded nodes must expose their fixed length in Schema metadata",
        )
      }
    "array" =>
      if !schema_has_constraint(node, "count=") {
        lint_issue(
          issues,
          "missing-repeat-count",
          LintError,
          path,
          "fixed arrays must expose their repeat count in Schema metadata",
        )
      }
    "tagged" =>
      if schema_has_constraint(node, "variants=dynamic") {
        lint_issue(
          issues,
          "dynamic-tagged-variants",
          LintWarning,
          path,
          "tagged variants are selected dynamically, so static tools cannot enumerate branch schemas",
        )
      }
    "until-eof-array" =>
      lint_issue(
        issues,
        "until-eof-region",
        LintWarning,
        path,
        "until_eof depends on the enclosing region boundary; prefer an explicit bounded region when the protocol provides one",
      )
    "remaining-bytes" | "remaining-view" =>
      lint_issue(
        issues,
        "remaining-region",
        LintWarning,
        path,
        "remaining_* consumes the entire enclosing region; keep it inside a protocol-defined bounded region",
      )
    _ => ()
  }
  for index, child in node.children {
    lint_node(child, child_path(path, child, index), issues)
  }
}

///|
/// 对任意 SchemaNode 执行确定性的静态检查。
pub fn lint_schema(schema : SchemaNode) -> Array[LintIssue] {
  let issues : Array[LintIssue] = []
  let root = if schema.name == "" { schema.kind } else { schema.name }
  lint_node(schema, root, issues)
  issues
}

///|
/// 直接检查 Codec 自带的 Schema 元数据。
pub fn[T] Codec::lint(self : Codec[T]) -> Array[LintIssue] {
  lint_schema(self.schema)
}
