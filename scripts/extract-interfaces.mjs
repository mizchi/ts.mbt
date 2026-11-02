// Extract interface information from TypeScript files using the compiler API
// The classic AST API; TypeScript 7 does not ship it, so the pinned
// `typescript-6` is used.
import ts from 'typescript-6';
import fs from 'fs';
import path from 'path';

function extractInterfaces(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const sourceFile = ts.createSourceFile(
    filePath,
    content,
    ts.ScriptTarget.Latest,
    true
  );

  const interfaces = [];

  function visit(node) {
    if (ts.isInterfaceDeclaration(node)) {
      const iface = {
        name: node.name.text,
        fields: []
      };

      for (const member of node.members) {
        if (ts.isPropertySignature(member) || ts.isMethodSignature(member)) {
          const fieldName = member.name ? getPropertyName(member.name) : '<unknown>';
          const fieldType = member.type ? content.slice(member.type.pos, member.type.end).trim() : 'any';
          const isOptional = !!member.questionToken;
          const isMethod = ts.isMethodSignature(member);

          iface.fields.push({
            name: fieldName,
            type: fieldType,
            optional: isOptional,
            method: isMethod
          });
        } else if (ts.isIndexSignatureDeclaration(member)) {
          iface.fields.push({
            name: '<index>',
            type: member.type ? content.slice(member.type.pos, member.type.end).trim() : 'any',
            optional: false,
            method: false
          });
        } else if (ts.isConstructSignatureDeclaration(member)) {
          iface.fields.push({
            name: '<new>',
            type: member.type ? content.slice(member.type.pos, member.type.end).trim() : 'any',
            optional: false,
            method: true
          });
        } else if (ts.isCallSignatureDeclaration(member)) {
          iface.fields.push({
            name: '<call>',
            type: member.type ? content.slice(member.type.pos, member.type.end).trim() : 'any',
            optional: false,
            method: true
          });
        }
      }

      interfaces.push(iface);
    }

    ts.forEachChild(node, visit);
  }

  function getPropertyName(name) {
    if (ts.isIdentifier(name)) {
      return name.text;
    } else if (ts.isStringLiteral(name)) {
      return name.text;
    } else if (ts.isNumericLiteral(name)) {
      return name.text;
    } else if (ts.isComputedPropertyName(name)) {
      return '<computed>';
    }
    return '<unknown>';
  }

  visit(sourceFile);
  return interfaces;
}

// Main
const args = process.argv.slice(2);
if (args.length === 0) {
  console.error('Usage: node extract-interfaces.mjs <file.d.ts>');
  process.exit(1);
}

const filePath = args[0];
const interfaces = extractInterfaces(filePath);
console.log(JSON.stringify(interfaces, null, 2));
