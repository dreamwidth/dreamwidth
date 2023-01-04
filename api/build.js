const $RefParser = require("@apidevtools/json-schema-ref-parser");
const YAML = require('yaml');
const fs = require("fs");
const path = require("path");

async function* walk(dir) {
    for await (const d of await fs.promises.opendir(dir)) {
        const entry = path.join(dir, d.name);
        if (d.isDirectory()) yield* walk(entry);
        else if (d.isFile()) yield entry;
    }
}


async function main() {
  for await (const p of walk('src/')) {
    let out_path = p.replace('src/', 'dist/')
    $RefParser.dereference(p, (err, schema) => {
      if (err) {
        console.log(p)
        console.error(err);
      }
      else {
        // console.log(YAML.stringify(schema));
        fs.writeFile(out_path, YAML.stringify(schema), err => {
          if (err) {
            console.error(err);
          }
          // file written successfully
        });
      }
    });
  }
}

main();