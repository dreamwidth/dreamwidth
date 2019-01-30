
CodeMirror.defineSimpleMode("s2", {

  start: [
    // Multi-token checks, appear first so that the group matches happen before the individual ones.
    {regex: /(\$\*?)([\w_]*)(->)([\w_]*)/, token: [null, "variable-2", "operator", "def"]},
    {regex: /(\$\*?)([\w_]*)(\.)([\w_]*)/, token: [null, "variable-2", "operator", "property"]},
    {regex: /(property)(\s+)(use)(\s+)([\w_]+)/, token: ["keyword", null, "builtin", null, "variable-2"]},
    {regex: /(set)(\s+)([\w_]+)/, token: ["keyword", null, "variable-2"]},
    {regex: /([\w_]+)(::)([\w_]*)/, token: ["type", "operator", "def"]},
    {regex: /(function)(\s+)([A-Za-z0-9_]+)/, token: ["keyword", null, "def"]},
    {regex: /(var)(\s+)(readonly)(\s+)([\[\]\(\){}\w]+)(\s+)([\w$]+)/, token: ["keyword", null, "property", null, "type", null, "variable-3"]},
    {regex: /(var)(\s+)([\[\]\(\)\{\}\w]+)(\s+)([\w$]+)/, token: ["keyword", null, "type", null, "variable-2"]},

    // try and shift into CSS or XML mode in blockquoted content, because it's
    // usually one of the two.
    {regex: /"""(?=<)/, token: "string", mode: {spec: "xml", end: /"""/}},
    {regex: /"""/, token: "string", mode: {spec: "css", end: /"""/}},

    // Highlighting for various reserved words.
    {regex: /(?:class|else|elseif|function|if|builtin|property|var|while|foreach|while|for|not|and|or|xor|extends|return|delete|defined|new|true|false|reverse|size|isnull|instanceof|as|isa|break|continue)\b/,
      token: "keyword"},
    {regex: /(?:use|set|print|println|push|pop)\b/, token: "builtin"},
    {regex: /(?:layerinfo|propgroup)\b/, token: "meta"},
    {regex: /(?:builtin|readonly|static)\b/, token: "property"},
    {regex: /(?:string|int|bool)\b/, token: "type"},

    // Simple type checks
    {regex: /true|false|null|undefined/, token: "atom"},
    {regex: /0x[a-f\d]+|[-+]?(?:\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/i, token: "number"},
    {regex: /#.*/, token: "comment"},
    {regex: /[-+\/*=<>!.]+/, token: "operator"},
    {regex: /"(?:[^\\]|\\.)*?(?:"|$)/, token: "string"},
    {regex: /(\$\*?)([\w_]*)/, token: [null, "variable-2"]},

    // indent and dedent properties guide autoindentation
    {regex: /[\{\[\(]/, indent: true},
    {regex: /[\}\]\)]/, dedent: true},


  ],

  // The meta property contains global information about the mode. It
  // can contain properties like lineComment, which are supported by
  // all modes, and also directives like dontIndentStates, which are
  // specific to simple modes.
  meta: {
    dontIndentStates: ["comment"],
    lineComment: "//"
  }
});
