
| ARC v0.1.0 Language Specification |  |
| ----: | ----: |
| Revision 2 | 23 March 2026 |


# THIS DOCUMENTATION IS CURRENTLTY A WIP. COMING SOON 👀
# 1. Introduction
## 1.1 Purpose
ARC is the native application language of CircleOS. It is designed to provide human-readable source distribution and easily modifiable source code, while preserving signature and certificate-based trust. ARC is *intentionally* interpreted, and not compiled, to encourage curiosity and open source. In fact, if any closed-source ARC programs are discovered, SuperCode Studios makes a committment to patching their method of closing the source. ARC is not intended to replace general-purpose programming languages, but rather as an easier and simpler method of creating userspace applications for CircleOS.
## 1.2 File Format

# 2. Execution Model
## 2.1 Invocation
ARC applications are executed using the following csh command:
```csh
arc filename.arc
```
The interpreter performs:
- Header parsing
- Signature and certificate validation
- Dependency validation
- Display initialisation
- Logic execution
- Persistence handling

## 2.2 Runtime characteristics
As of v0.1.0 ARCLang is single-threaded, Event polling based, and deterministic. There is no concurrency model as of version 0.1.0 but this will be fixed in later versions.

## 2.3 Memory model
Arc uses
- Dynamic memory allocation
- Reference based variable storage
- Automatic memory cleanup on exit
There is no manual memory management. (this may mean that developers cannot write better optimised programs if i write bad code but oh well)

# 3. Program structure
An ARC program consists of exactly four sections in this order:
1. Header
2. Display
3. Logic
4. Persistence
Each section must be terminated and marked properly for the program to be valid.

# 4. Header specification
## 4.1 Header Syntax
## 4.2 Core header fields
## 4.3 security fields
## 4.1 Dependency declaration and validation
## 4.5 Optional behaviour flags
