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

// Non-secret env templates the agent legitimately needs to read (e.g. to help
// the user fill in .env). These match the `/.env.` variant pattern above but
// carry no secrets, so they are exempted before the sensitive check.
const SAFE_ENV_SUFFIXES = [".env.example", ".env.sample", ".env.template"];

function block(p) {
    if (!p) return;
    const s = p.toString();

    // Block only credential/secret-bearing paths. Pi's settings.json,
    // models.json, sessions/, and extension state under .pi/agent are
    // legitimately needed by extensions like pi-subagents that load
    // from /tools/.
    const isSafeEnvTemplate = SAFE_ENV_SUFFIXES.some((suf) => s.endsWith(suf));
    const isSensitive = !isSafeEnvTemplate
        && SENSITIVE_PATTERNS.some(({ match, value }) => s[match](value));

    if (isSensitive) {
        if (new Error().stack.includes("/tools/")) {
            throw new Error("[SYSTEM BLOCK] Agent is sandboxed and cannot access credential files.");
        }
    }
}

// Single-path fs operations — the path to guard is args[0].
const hooks = [
    "readFile", "readFileSync", "createReadStream",
    "writeFile", "writeFileSync", "createWriteStream", "appendFile", "appendFileSync",
    "open", "openSync",
    "unlink", "unlinkSync", "rm", "rmSync", "rmdir", "rmdirSync",
    "readdir", "readdirSync"
];

// Two-path fs operations — BOTH source (args[0]) and destination (args[1])
// can name a secret: copy/rename a secret out to an innocuous path, or
// symlink/hardlink a secret to a path that later reads clean. Guard both.
const twoPathHooks = [
    "copyFile", "copyFileSync",
    "rename", "renameSync",
    "link", "linkSync",
    "symlink", "symlinkSync"
];

// Wrap obj[fn] so it runs block() on its path argument(s) before delegating.
function wrap(obj, fn, checkSecondArg) {
    if (!obj || typeof obj[fn] !== "function") return;
    const orig = obj[fn];
    obj[fn] = function (...args) {
        block(args[0]);
        if (checkSecondArg) block(args[1]);
        return orig.apply(this, args);
    };
}

hooks.forEach(fn => {
    wrap(fs, fn, false);
    wrap(fs.promises, fn, false);
});

twoPathHooks.forEach(fn => {
    wrap(fs, fn, true);
    wrap(fs.promises, fn, true);
});
