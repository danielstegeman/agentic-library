---
name: logging-architecture-guidelines
description: 'Architectural guidelines for writing logging in any language or framework. Covers what to log, where logging belongs in a layered architecture, correct severity levels, and conciseness. Use when generating or improving logging code, designing a logging strategy, or explaining logging best practices.'
---

# Logging Architecture Guidelines

These guidelines define how to design and write logging in any codebase. They apply to Python (`logging`/`logger.*`), PowerShell (`Write-Verbose`, `Write-Information`, `Write-Warning`), JavaScript/TypeScript (`console.*` and structured loggers), Java, C#, and any other language or framework.

## When to Apply These Guidelines

Apply these guidelines when:
- Writing or generating new logging statements
- Designing the logging strategy for a module, service, or script
- Deciding where in a call stack logging belongs
- Choosing the correct severity level for a message
- Explaining logging best practices to a developer

## Guidelines

### 1. Log Meaningful Inputs and Outputs Only

Log the inputs to a significant operation and its result. Do not log intermediate states, loop counters, or internal variable values that have no meaning outside the function.

```python
# Python — log what enters and what comes out
logger.info(f'Processing file: {filename}')
record_count = process(filename)
logger.info(f'Processed {record_count} records from {filename}')
```

```powershell
# PowerShell
Write-Information "Installing $Variant $TargetVersion to $Instance"
# ... installation ...
Write-Information "Installed $Variant $TargetVersion — exit code $exitCode"
```

### 2. Use a Single-Logger Architecture in Layered Code

In any codebase with multiple layers (orchestrator → service → helper), only the top-level entry point writes to the log. Helper and worker functions return values and raise/throw exceptions — they do not log.

**Why:** Helpers that log force callers to know what has already been reported. The same data point gets logged multiple times at different stack levels, inflating output and confusing operators. Helpers with no logging are trivially testable without asserting on output streams.

```python
# Correct: helper is silent, orchestrator logs
def install_package(name: str) -> bool:
    # raises on failure, returns True on success — no logging
    result = subprocess.run(['pip', 'install', name], capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode())
    return True

def run_installation(packages: list[str]) -> None:
    for name in packages:
        logger.info(f'Installing {name}')
        install_package(name)
        logger.info(f'Installed {name}')
```

```powershell
# Correct: helper is silent, Invoke-* function logs
function Install-Component { ... }  # no Write-* calls

function Invoke-Deployment {
    Write-Information "Installing $Component"
    Install-Component @params
    Write-Information "Installed $Component — exit $LASTEXITCODE"
}
```

### 3. Do Not Log to Trace Control Flow

Logging is not a substitute for a debugger or a step-trace. Do not emit messages solely to record which branch was taken or which function was entered. Code structure communicates flow; log statements communicate business data.

```python
# Wrong — traces flow, adds no data
logger.debug('Entering validate_order')
validate_order(order)
logger.debug('Exiting validate_order')

# Right — logs only when something notable happened
result = validate_order(order)
if not result.valid:
    logger.warning(f'Order {order.id} failed validation: {result.reason}')
```

### 4. Log Each Value Once Per Execution Path

Once a value has been emitted to the log, do not repeat it further down the same execution path. Each log entry should signal a distinct event. If the value changes, log the new value with context explaining the change.

### 5. Summarise at Boundaries, Not Per Item

For batch or iterative operations, emit a single summary at the operation boundary rather than one line per iteration.

```python
# Wrong
for row in rows:
    logger.info(f'Processed row {row.id}')

# Right
logger.info(f'Batch complete: {len(rows)} rows processed, {error_count} errors')
```

### 6. Use the Correct Severity Level

Choose the level that matches the significance and urgency of the message:

| Intent | Python | PowerShell | JS/TS |
|---|---|---|---|
| Fine-grained operational trace | `logger.debug` | `Write-Verbose` | `console.debug` |
| Significant business milestone | `logger.info` | `Write-Information` | `console.info` |
| Recoverable anomaly | `logger.warning` | `Write-Warning` | `console.warn` |
| Non-terminating failure | `logger.error` | `$PSCmdlet.WriteError()` | `console.error` |
| Terminating failure | `raise` | `$PSCmdlet.ThrowTerminatingError()` | `throw` |

- Reserve DEBUG/Verbose for detail that is only useful when actively diagnosing a problem. Gate it so it does not appear in routine production output.
- Do not use INFO/Information for messages that fire on every iteration of a loop.
- Do not reach for a higher severity than the situation warrants — cry-wolf warnings train operators to ignore them.

### 7. Keep Messages Short and Structured

Write log messages that are one line, contain key identifiers, and omit prose. Structured key=value or interpolated formats are preferred over natural-language sentences.

```python
# Preferred
logger.info(f'order={order_id} status={status} amount={amount:.2f}')

# Avoid
logger.info(
    f'The order with id {order_id} has now transitioned to the status {status}. '
    f'The total amount is {amount}.'
)
```
