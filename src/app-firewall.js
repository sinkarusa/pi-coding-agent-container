const fs = require("fs");

function block(p) {
    if (!p) return;
    const s = p.toString();

    // Block only credential/secret-bearing paths. Pi's settings.json,
    // models.json, sessions/, and extension state under .pi/agent are
    // legitimately needed by extensions like pi-subagents that load
    // from /tools/.
    const isSensitive =
        s.includes("auth.json") ||
        s.includes("credentials.json") ||
        s.includes("/.pi/agent/.secrets") ||
        s.includes("gh_") ||
        s.includes("/.secrets/") ||
        s.endsWith(".env") || s.includes("/.env.");

    if (isSensitive) {
        if (new Error().stack.includes("/tools/")) {
            throw new Error("[SYSTEM BLOCK] Agent is sandboxed and cannot access credential files.");
        }
    }
}

// Intercept all major filesystem operations
const hooks = [
    "readFile", "readFileSync", "createReadStream", 
    "writeFile", "writeFileSync", "createWriteStream", "appendFile", "appendFileSync",
    "open", "openSync", 
    "unlink", "unlinkSync", "rm", "rmSync", "rmdir", "rmdirSync",
    "readdir", "readdirSync"
];

hooks.forEach(fn => {
    // Hook standard fs callbacks/sync methods
    if (fs[fn]) {
        const orig = fs[fn];
        fs[fn] = function(...args) { 
            block(args[0]); 
            return orig.apply(this, args); 
        };
    }
    // Hook fs.promises methods
    if (fs.promises && fs.promises[fn]) {
        const origP = fs.promises[fn];
        fs.promises[fn] = function(...args) { 
            block(args[0]); 
            return origP.apply(this, args); 
        };
    }
});