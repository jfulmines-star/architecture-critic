# Security Policy

## Overview

Architecture Critic is a read-only analysis tool. It reads your codebase and spec files, sends them to your configured LLM provider, and returns a verdict. It does not write files, modify config, execute builds, or transmit data to any third party.

## What This Skill Does

- Reads source files from a specified local repository path (read-only)
- Reads your existing OpenClaw config to find your configured LLM API key
- Sends a structured prompt (codebase snapshot + spec) to your LLM provider
- Writes a verdict markdown file to your local workspace
- Prints the verdict to stdout

## What This Skill Does NOT Do

- Does not store, log, or transmit API keys or credentials to any third party
- Does not modify any source files, config files, or deployment settings
- Does not make network requests other than to your configured LLM provider API
- Does not install dependencies or execute build commands
- Does not have persistent background processes

## API Key Handling

The script reads your LLM API key from your existing OpenClaw config (`~/.openclaw/openclaw.json`) or from standard environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`). The key is passed in-memory to the LLM API call only. It is never written to disk, logged, or sent anywhere other than the configured provider endpoint.

## Supported Providers

All API calls go directly to the official provider endpoints:
- Anthropic: `https://api.anthropic.com/v1/messages`
- OpenAI: `https://api.openai.com/v1/chat/completions`
- Google: `https://generativelanguage.googleapis.com/v1beta/`

No proxy, no relay, no third-party intermediary.

## Reporting a Vulnerability

If you discover a security issue, please open a GitHub issue at:
https://github.com/jfulmines-star/architecture-critic/issues

Include a description of the issue and steps to reproduce. We respond within 48 hours.
