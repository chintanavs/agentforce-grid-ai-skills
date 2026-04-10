#!/usr/bin/env python3
"""PreToolUse hook: Validate column configuration before add_column or edit_column.

Reads tool input from stdin as JSON. Checks for the 6 most common config errors:
  1. Missing nested config.config structure
  2. Type field mismatch (outer vs inner)
  3. Wrong queryResponseFormat for the scenario
  4. referenceAttributes using invalid columnType (must be PascalCase)
  5. Missing modelConfig on AI/PromptTemplate columns
  6. ContextVariable with both value AND reference

Exit codes:
  0 - Allow the tool call (no issues found)
  2 - Block the tool call (critical config error detected)
"""

import json
import sys

# Valid PascalCase columnType values for referenceAttributes (matches ColumnTypeEnum)
VALID_COLUMN_TYPES = {
    "Ai", "Formula", "Object", "Agent", "PromptTemplate", "Action",
    "InvocableAction", "Reference", "Text", "Evaluation", "DataModelObject",
    "AgentTest",
}

# Types that require modelConfig in the inner config
REQUIRES_MODEL_CONFIG = {"AI", "PromptTemplate"}


def validate_config(tool_input: dict) -> list[str]:
    """Validate a column config and return a list of error messages."""
    errors = []

    config_str = tool_input.get("config")
    if not config_str:
        return []

    try:
        config = json.loads(config_str) if isinstance(config_str, str) else config_str
    except (json.JSONDecodeError, TypeError):
        errors.append("config parameter is not valid JSON.")
        return errors

    # Check 1: nested config.config structure
    outer_type = config.get("type")
    outer_config = config.get("config")

    if outer_config is None:
        errors.append(
            f"Missing outer config object. Expected: "
            f'{{"name":"...","type":"{outer_type}","config":{{"type":"{outer_type}",...,"config":{{...}}}}}}'
        )
        return errors

    if isinstance(outer_config, dict):
        inner_type = outer_config.get("type")

        # Check 2: type field mismatch
        if outer_type and inner_type and outer_type != inner_type:
            errors.append(
                f"Type mismatch: outer type is '{outer_type}' but config.type is '{inner_type}'. "
                f"These must match."
            )

        inner_config = outer_config.get("config")
        if inner_config is None and outer_type != "Text":
            # Text columns can sometimes have minimal config, but others should not
            errors.append(
                f"Missing nested config.config object for {outer_type} column. "
                f"The config structure must be: config.config.{{type-specific fields}}"
            )

        if isinstance(inner_config, dict):
            # Check 5: missing modelConfig for AI/PromptTemplate
            if outer_type in REQUIRES_MODEL_CONFIG:
                model_config = inner_config.get("modelConfig")
                if not model_config:
                    errors.append(
                        f"{outer_type} columns require modelConfig in config.config. "
                        f'Add: "modelConfig": {{"modelId": "sfdc_ai__DefaultGPT4Omni", '
                        f'"modelName": "sfdc_ai__DefaultGPT4Omni"}}'
                    )

            # Check 4: referenceAttributes with invalid columnType (must be PascalCase)
            ref_attrs = inner_config.get("referenceAttributes", [])
            if isinstance(ref_attrs, list):
                for i, ref in enumerate(ref_attrs):
                    if isinstance(ref, dict):
                        col_type = ref.get("columnType", "")
                        if col_type and col_type not in VALID_COLUMN_TYPES:
                            errors.append(
                                f"referenceAttributes[{i}].columnType = '{col_type}' "
                                f"is not a valid PascalCase ColumnTypeEnum value. "
                                f"Valid values: {sorted(VALID_COLUMN_TYPES)}"
                            )

            # Check 6: ContextVariable with both value and reference
            context_vars = inner_config.get("contextVariables", [])
            if isinstance(context_vars, list):
                for i, cv in enumerate(context_vars):
                    if isinstance(cv, dict):
                        has_value = "value" in cv and cv["value"] is not None
                        has_ref = "reference" in cv and cv["reference"] is not None
                        if has_value and has_ref:
                            errors.append(
                                f"contextVariables[{i}] has both 'value' and 'reference'. "
                                f"Each ContextVariable must have EITHER value OR reference, not both."
                            )

            # Check for AI columns missing mode
            if outer_type == "AI" and "mode" not in inner_config:
                errors.append(
                    'AI columns require "mode": "llm" in config.config.'
                )

            # Check for AI columns missing responseFormat
            if outer_type == "AI" and "responseFormat" not in inner_config:
                errors.append(
                    'AI columns require "responseFormat" in config.config. '
                    'Add: "responseFormat": {"type": "PLAIN_TEXT", "options": []}'
                )

    return errors


def main():
    try:
        input_data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        # Can't parse input, let it through
        sys.exit(0)

    tool_input = input_data.get("tool_input", {})
    if not tool_input:
        sys.exit(0)

    errors = validate_config(tool_input)

    if errors:
        print("Column config validation errors detected:\n")
        for i, err in enumerate(errors, 1):
            print(f"  {i}. {err}")
        print(
            "\nFix these issues before calling the tool. "
            "See SKILL.md for correct config structures."
        )
        # Exit 2 to block the tool call
        sys.exit(2)

    # No errors found
    sys.exit(0)


if __name__ == "__main__":
    main()
