# Pi instructions

- Inspect existing files and conventions before making changes.
- Make the smallest safe change that satisfies the request.
- Do not expose credentials, tokens, private keys, or session data.
- Prefer existing project tools and conventions.
- Run relevant validation after making changes.
- Summarize changed files and validation results.
- HARD REQUIREMENT: when an agent needs two or more related answers, it MUST invoke the structured questionnaire tool before presenting those questions. Do not substitute a prose list or several individual questions. Use the normal question tool only for one genuinely simple clarification.
- Questionnaires should contain 3–7 prioritized questions with stable IDs, concise choices, and an Other option when practical. Agents may and should run additional questionnaire rounds when answers reveal material gaps or new decisions.
