const fs = require("fs");

// Sensitive path patterns — any fs access matching these from the agent
// sandbox (/tools/) is blocked. Edit this list to change the policy.
const SENSITIVE_PATTERNS = [
    { match: "includes", value: "auth.json",            reason: "pi auth tokens" },
    { match: "includes", value: "credentials.json",     reason: "OAuth credentials" },
    { match: "includes", value: "/.pi/agent/.secrets",  reason: "pi secret store" },
    { match: "includes", value: "/run/secrets/gh_",     reason: "GitHub token secret files" },
    { match: "includes", value: "/.secrets/",           reason: "host secrets directory" },
    { match: "endsWith", value: ".env",                 reason: "environment file" },
    { match: "includes", value: "/.env.",               reason: "environment file variants" },
];

function block(p) {
    if (!p) return;
    const s = p.toString();

    // Block only credential/secret-bearing paths. Pi's settings.json,
    // models.json, sessions/, and extension state under .pi/agent are
    // legitimately needed by extensions like pi-subagents that load
    // from /tools/.
    const isSensitive = SENSITIVE_PATTERNS.some(({ match, value }) => s[match](value));

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
