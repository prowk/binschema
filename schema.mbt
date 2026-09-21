///|
/// Codec 的可检查结构描述。它不参与编解码，只描述协议形状、名称与约束。
pub(all) struct SchemaNode {
  name : String
  kind : String
  constraints : Array[String]
  children : Array[SchemaNode]
} derive(Eq, Debug, ToJson)

///|
pub extend SchemaNode with Eq::{not_equal, equal}

///|
pub extend SchemaNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SchemaNode with ToJson::{to_json}

///|
pub fn SchemaNode::leaf(kind : String) -> SchemaNode {
  { name: "", kind, constraints: [], children: [], }
}

///|
pub fn SchemaNode::node(
  kind : String,
  children : Array[SchemaNode],
  constraints? : Array[String] = [],
) -> SchemaNode {
  { name: "", kind, constraints: constraints.copy(), children: children.copy(), }
}

///|
pub fn SchemaNode::with_name(self : SchemaNode, name : String) -> SchemaNode {
  {
    name,
    kind: self.kind,
    constraints: self.constraints.copy(),
    children: self.children.map(fn(child) { child.copy() }),
  }
}

///|
pub fn SchemaNode::with_constraint(
  self : SchemaNode,
  constraint : String,
) -> SchemaNode {
  let constraints = self.constraints.copy()
  constraints.push(constraint)
  {
    name: self.name,
    kind: self.kind,
    constraints,
    children: self.children.map(fn(child) { child.copy() }),
  }
}

///|
pub fn SchemaNode::copy(self : SchemaNode) -> SchemaNode {
  {
    name: self.name,
    kind: self.kind,
    constraints: self.constraints.copy(),
    children: self.children.map(fn(child) { child.copy() }),
  }
}

///|
fn SchemaNode::render_lines(
  self : SchemaNode,
  depth : Int,
  output : Array[String],
) -> Unit {
  let mut indent = ""
  for _ in 0..<depth {
    indent = indent + "  "
  }
  let label = if self.name == "" {
    self.kind
  } else {
    self.name + " : " + self.kind
  }
  let suffix = if self.constraints.length() == 0 {
    ""
  } else {
    " [" + self.constraints.join(", ") + "]"
  }
  output.push(indent + label + suffix)
  for child in self.children {
    child.render_lines(depth + 1, output)
  }
}

///|
/// 将 Schema 树渲染成稳定、适合 CLI/文档展示的文本。
pub fn SchemaNode::render(self : SchemaNode) -> String {
  let lines : Array[String] = []
  self.render_lines(0, lines)
  lines.join("\n")
}
