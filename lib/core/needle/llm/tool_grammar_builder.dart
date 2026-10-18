import '../../models/tool_definition.dart';

/// Dynamically builds a GBNF grammar string from the active device's
/// [ToolDefinition] list so `llama.cpp` only samples valid tool names and JSON.
class ToolGrammarBuilder {
  ToolGrammarBuilder._();

  static String buildGrammar(List<ToolDefinition> tools) {
    final toolNames = tools.map((t) => '"\\"${t.name}\\""').toList();
    final toolRule = toolNames.isNotEmpty ? toolNames.join(' | ') : 'string';

    return '''
root   ::= "{\\"calls\\":[" call ("," call)* "]}"
call   ::= "{\\"tool\\":" tool ",\\"params\\":" object "}"
tool   ::= $toolRule
object ::= "{}" | "{" pair ("," pair)* "}"
pair   ::= string ":" value
value  ::= string | number | "true" | "false"
string ::= "\\"" ([^"\\\\] | "\\\\" .)* "\\""
number ::= "-"? [0-9]+ ("." [0-9]+)?
''';
  }
}
