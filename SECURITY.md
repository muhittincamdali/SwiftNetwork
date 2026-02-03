# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take the security of SwiftNetwork seriously. If you have discovered a security vulnerability, we appreciate your help in disclosing it to us in a responsible manner.

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to the repository owner. You can find contact information on the GitHub profile.

Please include the following information:

- Type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

### What to Expect

- A confirmation of receipt within 48 hours
- An assessment of the vulnerability within 7 days
- Regular updates on our progress
- Credit for responsible disclosure (if desired)

## Security Best Practices

When using SwiftNetwork in your projects:

1. **Always use HTTPS** - Never disable SSL verification in production
2. **Enable certificate pinning** - For sensitive applications
3. **Sanitize inputs** - Never trust user input in request parameters
4. **Secure credentials** - Use Keychain for storing sensitive data
5. **Keep updated** - Always use the latest version
