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
  if (!fs.existsSync("dist/")) {
    fs.mkdir("dist/", err => {
      if (err) {
        console.error(err);
      }
    });
  }

  for await (const p of walk('src/')) {
    let out_path = p.replace('src/', 'dist/');
    $RefParser.dereference(p, (err, schema) => {
      if (err) {
        console.log(p);
        console.error(err);
      }
      else {
        let out_dir = out_path.substring(0, out_path.lastIndexOf("/"));
        if (!fs.existsSync(out_dir)) {
          fs.mkdir(out_dir, err => {
            if (err) {
              console.error(err);
            }
          });
        }

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