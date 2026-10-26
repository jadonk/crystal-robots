// Turns the code reader's and checker's messages (src/compiler/parser.cr,
// src/compiler/checker.cr) into plain words for first-time programmers.
// Each known message is matched whole and keeps the names from the
// visitor's code; anything not listed here is shown unchanged rather than
// guessed at, so a new or unexpected message is never garbled.
const MESSAGES = [
  [/^Cannot reduce .*$/s,
    () => "This part of the code doesn't make sense to the robot yet. Look for a missing `end`, an extra or missing parenthesis, or a typo."],
  [/^Unexpected character (.+)$/,
    (_, ch) => `The character ${ch} isn't part of the robot language. Check for a typo.`],
  [/^Program needs more than [\d,]+ passes$/,
    () => "This robot is too complicated to read. Try splitting long lines or using fewer nested parentheses."],
  [/^Program is too large to parse .*$/,
    () => "This robot is too long to read. Try a shorter program."],
  [/^function (\w+) is defined twice$/,
    (_, name) => `There are two definitions named ${name}. Rename or remove one of them.`],
  [/^(\w+) takes (\d+) arguments but is called with none$/,
    (_, name, n) => `${name} needs ${n} number${n === "1" ? "" : "s"} in parentheses, like ${name}(…).`],
  [/^(\w+) takes (\d+) arguments but is called with (\d+)$/,
    (_, name, n, got) => `${name} needs ${n} number${n === "1" ? "" : "s"}, but ${got} ${got === "1" ? "was" : "were"} given.`],
  [/^undefined variable or function (\w+)$/,
    (_, name) => `The robot doesn't know the name ${name}. Check the spelling, or give it a value first.`],
  [/^undefined variable (\w+)$/,
    (_, name) => `The robot doesn't know the name ${name}. Give it a value before using it.`],
  [/^undefined function (\w+)$/,
    (_, name) => `There's no command named ${name}. Check the spelling, or see the manual's list of commands.`],
  [/^call depth exceeded (\d+) in (\w+)$/,
    (_, depth, name) => `${name} kept calling itself (more than ${depth} times deep), so the robot stopped and started over.`],
  [/^runtime error: (.*)$/s,
    (_, rest) => `Problem while running: ${friendlyError(rest)}`],
];

export function friendlyError(message) {
  const text = String(message || "Something went wrong.").trim();
  for (const [pattern, explain] of MESSAGES) {
    const match = text.match(pattern);
    if (match) return explain(...match);
  }
  return text;
}
