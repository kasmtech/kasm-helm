import yaml
import logging
import sys
import re
import json
import unicodedata
import os
import difflib
import argparse

# Logging setup
logger = logging.getLogger("KasmValidator")
logger.setLevel(logging.DEBUG)
log_formatter = logging.Formatter('[%(levelname)s] %(message)s')
_log_dir = os.environ.get("VALIDATE_LOG_DIR", "")
if _log_dir:
    _log_path = os.path.join(_log_dir, "validation_errors.log")
    file_handler = logging.FileHandler(_log_path, mode='w')
    file_handler.setFormatter(log_formatter)
    file_handler.setLevel(logging.DEBUG)
    logger.addHandler(file_handler)
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(log_formatter)
console_handler.setLevel(logging.WARNING)
logger.addHandler(console_handler)

ALLOWED_FSTRING_VARS = {
    'server_id', 'server_hostname', 'server_external_fqdn',
    'provider_name', 'domain', 'ad_join_credential',
    'connection_username', 'connection_password', 'checking_jwt',
    'manager_token', 'upstream_auth_address'
}

CERTIFICATE_FIELDS = {
    ("oci_vm_configs", "oci_private_key"): "tls_private",
    ("oci_vm_configs", "oci_ssh_public_key"): "ssh_public",
    ("oci_dns_configs", "oci_private_key"): "tls_private",
    ("user_attributes", "ssh_private_key"): "ssh_private",
    ("user_attributes", "ssh_public_key"): "ssh_public",
    ("aws_configs", "aws_ec2_private_key"): "ssh_private",
    ("aws_configs", "aws_ec2_public_key"): "ssh_public",
    ("saml_config", "sp_private_key"): "tls_private",
    ("azure_configs", "azure_ssh_public_key"): "ssh_public",
}

FORCE_JSON_FIELDS = {"connection_info"}

# Regex patterns
UUID_RE = re.compile(r'^[a-fA-F0-9]{32}$')
UUID_TEMPLATE_RE = re.compile(r'^\$\{uuid:[^}]+\}$')
PEM_TLS_PRIVATE_KEY_RE = re.compile(r'-----BEGIN (RSA |EC |)PRIVATE KEY-----[\s\S]+-----END (RSA |EC |)PRIVATE KEY-----', re.MULTILINE)
PEM_OPENSSH_PRIVATE_KEY_RE = re.compile(r'-----BEGIN OPENSSH PRIVATE KEY-----[\s\S]+-----END OPENSSH PRIVATE KEY-----', re.MULTILINE)
SSH_PUBLIC_KEY_RE = re.compile(r'^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2-nistp)[^\n\r]+', re.MULTILINE)
FSTRING_VAR_PATTERN = re.compile(r'{([^{}]+)}')
DOUBLE_CURLY_PATTERN = re.compile(r'{{[^{}]*}}')
BASH_VAR_PATTERN = re.compile(r'\$\{([^{}]+)\}|\$([a-zA-Z_][\w]*)')
BASH_SINGLE_CURLY = re.compile(r'(?<!{){([^{}]+)}(?!})')

def is_uuid(val):
    if isinstance(val, str):
        s = val.replace('-', '')
        return bool(UUID_RE.match(s)) or bool(UUID_TEMPLATE_RE.match(val))
    return False

def validate_certificate_field(value, field_type):
    if not isinstance(value, str):
        return False
    if field_type == "tls_private":
        if PEM_TLS_PRIVATE_KEY_RE.search(value):
            return True
        if PEM_OPENSSH_PRIVATE_KEY_RE.search(value):
            return True
        return False
    elif field_type == "ssh_private":
        return bool(PEM_OPENSSH_PRIVATE_KEY_RE.search(value) or PEM_TLS_PRIVATE_KEY_RE.search(value))
    elif field_type == "ssh_public":
        return bool(SSH_PUBLIC_KEY_RE.match(value.strip()))
    return False

def example_certificate(field_type):
    if field_type == "tls_private":
        return (
            "-----BEGIN RSA PRIVATE KEY-----\n"
            "MIIEogIBAAKCAQEA7fakekeydatafakekeydatafakekeydataf\n"
            "-----END RSA PRIVATE KEY-----"
        )
    elif field_type == "ssh_private":
        return (
            "-----BEGIN OPENSSH PRIVATE KEY-----\n"
            "b3BlbnNzaC1rZXktZmFrZWZha2VsbG9sZWxsbw==\n"
            "-----END OPENSSH PRIVATE KEY-----"
        )
    elif field_type == "ssh_public":
        return (
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7examplekeycomment"
        )
    return ""

def normalize_whitespace(val):
    if not isinstance(val, str): return val, False
    normalized = unicodedata.normalize('NFKC', val)
    stripped = normalized.strip()
    changed = (val != stripped)
    return stripped, changed

def try_type_conversions(val, expected_type):
    suggestions = []
    if not isinstance(val, str): return suggestions
    try:
        if expected_type == 'INTEGER':
            if val.isdigit():
                suggestions.append('Can be safely converted to integer')
        elif expected_type == 'FLOAT':
            float(val)
            suggestions.append('Can be safely converted to float')
        elif expected_type == 'BOOLEAN':
            if val.lower() in ('true', 'false'):
                suggestions.append('Can be safely converted to boolean')
    except Exception:
        pass
    return suggestions

def json_minor_fixes(val):
    attempts = []
    if not isinstance(val, str): return attempts
    try:
        parsed = json.loads(val)
        attempts.append(('Standard JSON parse succeeds', parsed))
        return attempts
    except Exception as e:
        attempts.append((f'Standard JSON parse failed: {e}', None))
    single_quote_fix = val.replace("'", '"')
    try:
        parsed = json.loads(single_quote_fix)
        attempts.append(('After replacing single with double quotes', parsed))
    except Exception as e:
        attempts.append((f'After single-to-double quote fix: {e}', None))
    trailing_comma_fix = re.sub(r',(\s*[\]}])', r'\1', val)
    try:
        parsed = json.loads(trailing_comma_fix)
        attempts.append(('After removing trailing commas', parsed))
    except Exception as e:
        attempts.append((f'After trailing comma fix: {e}', None))
    return attempts

def is_in_double_curly(idx, spans):
    return any(start <= idx < end for start, end in spans)

def check_startup_script(script_text):
    findings = []
    if not isinstance(script_text, str):
        return findings

    # Find double curly blocks and their spans
    double_curly_spans = [(m.start(), m.end()) for m in DOUBLE_CURLY_PATTERN.finditer(script_text)]

    # Check f-string variables for legality
    for match in FSTRING_VAR_PATTERN.finditer(script_text):
        idx = match.start()
        var = match.group(1).strip("'\"")
        if is_in_double_curly(idx, double_curly_spans):
            continue
        if var not in ALLOWED_FSTRING_VARS:
            findings.append(f"Illegal f-string variable: {{{var}}} (must be one of {sorted(ALLOWED_FSTRING_VARS)})")

    # Ambiguous curly braces: only flag if not in allowed f-string variables and not inside double curly
    for match in BASH_SINGLE_CURLY.finditer(script_text):
        idx = match.start()
        block = match.group(1).strip("'\"")
        if is_in_double_curly(idx, double_curly_spans):
            continue
        # ---- THE FIX: Just check membership, not position
        if block in ALLOWED_FSTRING_VARS:
            continue
        findings.append(f"Ambiguous or invalid curly-brace block: '{{{block}}}'. Use '{{{{...}}}}' for literal curly braces or ensure variable is allowed.")

    # Bash variable usage: ignore anything inside double curly
    for match in BASH_VAR_PATTERN.finditer(script_text):
        idx = match.start()
        var = match.group(1) or match.group(2)
        if is_in_double_curly(idx, double_curly_spans):
            continue
        if var and var not in ALLOWED_FSTRING_VARS and not var.startswith('{'):
            findings.append(f"Illegal Bash variable or ambiguous use: ${var}. Only allowed variables: {sorted(ALLOWED_FSTRING_VARS)}")

    # Bash/Powershell range/array blocks not escaped
    for match in re.finditer(r'(?<!{){\d+\.\.\d+}(?!})', script_text):
        idx = match.start()
        if is_in_double_curly(idx, double_curly_spans):
            continue
        findings.append("Possible invalid Bash/Powershell range/array block. Use '{{...}}' for literals.")

    return findings

def load_yaml(path):
    try:
        with open(path, 'r') as f:
            return yaml.safe_load(f)
    except Exception as e:
        logger.error(f"Failed to load YAML file {path}: {e}")
        sys.exit(1)

def collect_primary_keys(config, schema, debug):
    pk_lookup = {}
    for section_name, section_fields in schema.items():
        if not isinstance(section_fields, dict):
            continue
        for field_name, field_schema in section_fields.items():
            if field_schema.get('type', '').upper() == 'UUID' or field_name.endswith('_id'):
                section_data = config.get(section_name, [])
                if isinstance(section_data, dict):
                    section_data = [section_data]
                values = set()
                for item in section_data:
                    val = item.get(field_name)
                    if val is not None:
                        values.add(val)
                pk_lookup[(section_name, field_name)] = values
                if debug:
                    logger.debug(f"[{section_name}] PK field '{field_name}': {values}")
    return pk_lookup

def validate(schema, config, debug=False, partial=False):
    pk_lookup = collect_primary_keys(config, schema, debug)
    overall_passed = True

    for section_name, section_fields in schema.items():
        if not isinstance(section_fields, dict):
            continue

        errors = []
        section_data = config.get(section_name, None)
        print(f"Checking {section_name}...")
        if section_data is None:
            if partial:
                continue
            errors.append(f"Section '{section_name}' missing entirely from config.")
            if debug: logger.debug(f"{section_name} missing in config")
        else:
            if isinstance(section_data, dict):
                section_data = [section_data]
            if not isinstance(section_data, list):
                errors.append(f"Section data for '{section_name}' is not a list or dict")
            else:
                for idx, item in enumerate(section_data):
                    for field, field_schema in section_fields.items():
                        val = item.get(field)
                        expected_type = field_schema.get('type', '').upper()
                        # Whitespace normalization
                        if isinstance(val, str):
                            normalized_val, changed = normalize_whitespace(val)
                            if changed:
                                logger.warning(f"[{section_name}][item {idx}] Field '{field}' has leading/trailing or unusual whitespace/encoding.")
                        # Type conversion suggestions
                        for suggestion in try_type_conversions(val, expected_type):
                            logger.warning(f"[{section_name}][item {idx}] Field '{field}': {suggestion}")
                        # JSON fixes
                        if (
                            expected_type == 'JSON'
                            or (expected_type.startswith('VARCHAR') and field == 'value' and isinstance(val, str) and (val.lstrip().startswith('{') or val.lstrip().startswith('[')))
                            or field in FORCE_JSON_FIELDS
                        ):
                            # connection_info may be a dict or string
                            if isinstance(val, dict) or isinstance(val, list):
                                pass  # Already valid!
                            elif isinstance(val, str):
                                for desc, parsed in json_minor_fixes(val):
                                    if parsed is not None:
                                        logger.warning(f"[{section_name}][item {idx}] Field '{field}': {desc} (would parse as valid JSON).")
                                    else:
                                        logger.debug(f"[{section_name}][item {idx}] Field '{field}': {desc}")
                            else:
                                errors.append(f"[item {idx}] Field '{field}' should be a JSON object or string, got {type(val).__name__}")
                        # Startup_script template check
                        if field == 'startup_script' and isinstance(val, str):
                            for finding in check_startup_script(val):
                                logger.warning(f"[{section_name}][item {idx}] Field '{field}': {finding}")
                        # Strict type validation
                        if val is not None and expected_type:
                            if expected_type == 'JSON':
                                if not (isinstance(val, dict) or isinstance(val, list)):
                                    if isinstance(val, str):
                                        try:
                                            parsed = json.loads(val)
                                            if debug: logger.debug(f"[{section_name}][item {idx}] JSON string for '{field}' is valid JSON.")
                                        except Exception:
                                            errors.append(f"[item {idx}] Field '{field}' is marked as JSON but does not contain valid JSON data.")
                                    else:
                                        errors.append(f"[item {idx}] Field '{field}' is marked as JSON but is not a dict/list or valid JSON string.")
                            elif (expected_type.startswith('VARCHAR')
                                and field == 'value'
                                and isinstance(val, str)):
                                stripped_val = val.lstrip()
                                if stripped_val.startswith('{') or stripped_val.startswith('['):
                                    try:
                                        parsed = json.loads(val)
                                        if debug: logger.debug(f"[{section_name}][item {idx}] Field 'value' contains valid JSON.")
                                    except Exception:
                                        errors.append(f"[item {idx}] Field 'value' looks like JSON but is not valid JSON.")
                            elif (field in FORCE_JSON_FIELDS):
                                if not (isinstance(val, dict) or isinstance(val, list)):
                                    # Accept strings only if they're valid JSON
                                    if isinstance(val, str):
                                        try:
                                            parsed = json.loads(val)
                                        except Exception:
                                            errors.append(f"[item {idx}] Field '{field}' should contain valid JSON if not a YAML object.")
                                    else:
                                        errors.append(f"[item {idx}] Field '{field}' should be a JSON object, list, or JSON string, got {type(val).__name__}")
                            elif expected_type == 'BOOLEAN' and not isinstance(val, bool):
                                errors.append(f"[item {idx}] Field '{field}' expected BOOLEAN but got {type(val).__name__}")
                            elif expected_type == 'INTEGER' and not isinstance(val, int):
                                errors.append(f"[item {idx}] Field '{field}' expected INTEGER but got {type(val).__name__}")
                            elif expected_type == 'FLOAT' and not (isinstance(val, float) or isinstance(val, int)):
                                errors.append(f"[item {idx}] Field '{field}' expected FLOAT but got {type(val).__name__}")
                            elif expected_type == 'UUID' and not is_uuid(val):
                                errors.append(f"[item {idx}] Field '{field}' expected UUID or templated uuid string but got '{val}'")
                            elif expected_type.startswith('VARCHAR') and not isinstance(val, str):
                                errors.append(f"[item {idx}] Field '{field}' expected VARCHAR but got {type(val).__name__}")
                            elif expected_type == 'TIMESTAMP' and not isinstance(val, str):
                                errors.append(f"[item {idx}] Field '{field}' expected TIMESTAMP (as string) but got {type(val).__name__}")
                        if field_schema.get('required', False) and (val is None or val == ''):
                            errors.append(f"[item {idx}] Required field '{field}' missing or empty.")
                        fk = field_schema.get('foreign_key')
                        if fk and val is not None:
                            if '.' in fk:
                                target_section, target_field = fk.split('.', 1)
                                valid_set = pk_lookup.get((target_section, target_field), set())
                                if val not in valid_set:
                                    errors.append(f"[item {idx}] Foreign key '{field}' value '{val}' does not exist in '{target_section}.{target_field}'.")
                                    if debug:
                                        logger.debug(f"[{section_name}][item {idx}] FK '{field}' value '{val}' NOT FOUND in {target_section}.{target_field}: {valid_set}")
                                else:
                                    if debug:
                                        logger.debug(f"[{section_name}][item {idx}] FK '{field}' value '{val}' found in {target_section}.{target_field}")
                        # Cert/key validation
                        field_key = (section_name, field)
                        if field_key in CERTIFICATE_FIELDS:
                            if val not in (None, ''):
                                cert_type = CERTIFICATE_FIELDS[field_key]
                                if not validate_certificate_field(val, cert_type):
                                    errors.append(f"[item {idx}] Field '{field}' is not a valid {cert_type.replace('_', ' ').upper()} format.")
        if errors:
            overall_passed = False
            print(f"❌ {section_name.capitalize()} configuration failed!")
            logger.error(f"[{section_name}] Failed checks: {errors}")
        else:
            print(f"✅ {section_name.capitalize()} configuration passed!")
            logger.info(f"[{section_name}] All checks passed.")
    return overall_passed

def singularize(section):
    if section.endswith('ies'):
        return section[:-3] + 'y'
    elif section.endswith('ses'):
        return section[:-2]
    elif section.endswith('s'):
        return section[:-1]
    return section

def example_value(section, field, field_schema, counter=1):
    t = field_schema.get('type', '').upper()
    cert_key_type = CERTIFICATE_FIELDS.get((section, field))

    # Always output connection_info as an object
    if field == "connection_info":
        return {}

    if cert_key_type:
        return example_certificate(cert_key_type)

    # Foreign key references
    fk = field_schema.get('foreign_key')
    if fk:
        ref_field = fk.split('.')[-1]
        return f"${{uuid:{ref_field}:1}}"

    if t == 'UUID':
        # Singularize the section name and append "_id"
        singular_section = singularize(section)
        id_name = f"{singular_section}_id"
        return f"${{uuid:{id_name}:1}}"
    elif t == 'BOOLEAN':
        return False
    elif t == 'INTEGER':
        return 0
    elif t == 'FLOAT':
        return 0.0
    elif t == 'VARCHAR' or t == 'TEXT':
        return f"example_{field}"
    elif t == 'TIMESTAMP':
        return "2025-01-01 00:00:00"
    elif t == 'JSON':
        return {}
    else:
        return f"example_{field}"

def generate_example(schema):
    example = {}
    primary_key_values = {}  # (section, field) -> value

    # Alembic version
    if "alembic_version" in schema:
        example["alembic_version"] = schema["alembic_version"]

    # === FIRST PASS: Assign all primary key values ===
    for section_name, section_fields in schema.items():
        if section_name == "alembic_version" or not isinstance(section_fields, dict):
            continue
        for field, field_schema in section_fields.items():
            t = field_schema.get('type', '').upper()
            # Find primary key (endswith '_id' and matches singularized section)
            singular_section = singularize(section_name)
            pk_field = f"{singular_section}_id"
            if field == pk_field and t == 'UUID':
                value = f"${{uuid:{pk_field}:1}}"
                primary_key_values[(section_name, field)] = value
    # For sections with no "real" PK, you may need to add logic here.

    # === SECOND PASS: Build the example objects ===
    for section_name, section_fields in schema.items():
        if section_name == "alembic_version" or not isinstance(section_fields, dict):
            continue
        records = []
        item = {}
        for field, field_schema in section_fields.items():
            t = field_schema.get('type', '').upper()
            cert_key_type = CERTIFICATE_FIELDS.get((section_name, field))

            # connection_info is always {}
            if field == "connection_info":
                value = {}
            # Cert/key example
            elif cert_key_type:
                value = example_certificate(cert_key_type)
            # Foreign key reference: use actual value from the referenced section/field
            elif field_schema.get('foreign_key'):
                fk = field_schema['foreign_key']
                target_section, target_field = fk.split('.')
                ref_value = primary_key_values.get((target_section, target_field))
                # If the referenced value does not exist, generate a fallback
                if ref_value is None:
                    ref_value = f"${{uuid:{target_field}:1}}"
                value = ref_value
            # UUID (non-foreign key): use our remembered value if available
            elif t == 'UUID':
                value = primary_key_values.get((section_name, field), f"${{uuid:{field}:1}}")
            elif t == 'BOOLEAN':
                value = False
            elif t == 'INTEGER':
                value = 0
            elif t == 'FLOAT':
                value = 0.0
            elif t == 'VARCHAR' or t == 'TEXT':
                value = f"example_{field}"
            elif t == 'TIMESTAMP':
                value = "2025-01-01 00:00:00"
            elif t == 'JSON':
                value = {}
            else:
                value = f"example_{field}"
            item[field] = value
        records.append(item)
        example[section_name] = records

    with open('example_properties.yaml', 'w') as f:
        yaml.dump(example, f, sort_keys=False, default_flow_style=False)
    print("✅ Example configuration written to example_properties.yaml")

def diff_schemas(schema1, schema2):
    diffs = []
    sections1 = set(schema1.keys())
    sections2 = set(schema2.keys())
    added_sections = sections2 - sections1
    removed_sections = sections1 - sections2
    common_sections = sections1 & sections2

    if added_sections:
        diffs.append({"type": "section_added", "sections": sorted(added_sections)})
    if removed_sections:
        diffs.append({"type": "section_removed", "sections": sorted(removed_sections)})

    for section in sorted(common_sections):
        fields1 = schema1[section] if isinstance(schema1[section], dict) else {}
        fields2 = schema2[section] if isinstance(schema2[section], dict) else {}
        fieldnames1 = set(fields1.keys())
        fieldnames2 = set(fields2.keys())

        added_fields = fieldnames2 - fieldnames1
        removed_fields = fieldnames1 - fieldnames2
        common_fields = fieldnames1 & fieldnames2

        if added_fields:
            diffs.append({"type": "field_added", "section": section, "fields": sorted(added_fields)})
        if removed_fields:
            diffs.append({"type": "field_removed", "section": section, "fields": sorted(removed_fields)})

        for field in sorted(common_fields):
            f1 = fields1[field] or {}
            f2 = fields2[field] or {}
            prop_keys = set(f1.keys()) | set(f2.keys())
            changed_props = {}
            for prop in prop_keys:
                v1 = f1.get(prop)
                v2 = f2.get(prop)
                if v1 != v2:
                    changed_props[prop] = (v1, v2)
            if changed_props:
                diffs.append({
                    "type": "field_changed",
                    "section": section,
                    "field": field,
                    "changes": changed_props
                })
    return diffs

def format_structured_diff(diffs):
    lines = []
    for diff in diffs:
        if diff["type"] == "section_added":
            lines.append(f"Sections ADDED: {', '.join(diff['sections'])}")
        elif diff["type"] == "section_removed":
            lines.append(f"Sections REMOVED: {', '.join(diff['sections'])}")
        elif diff["type"] == "field_added":
            lines.append(f"Fields ADDED in [{diff['section']}]: {', '.join(diff['fields'])}")
        elif diff["type"] == "field_removed":
            lines.append(f"Fields REMOVED in [{diff['section']}]: {', '.join(diff['fields'])}")
        elif diff["type"] == "field_changed":
            lines.append(f"Field MODIFIED in [{diff['section']}].[{diff['field']}]:")
            for k, (v1, v2) in diff["changes"].items():
                lines.append(f"  - '{k}': {v1!r} -> {v2!r}")
    return "\n".join(lines)

def format_unified_diff(schema1, schema2, file1, file2):
    str1 = yaml.dump(schema1, sort_keys=True, default_flow_style=False).splitlines(keepends=True)
    str2 = yaml.dump(schema2, sort_keys=True, default_flow_style=False).splitlines(keepends=True)
    return ''.join(difflib.unified_diff(str1, str2, fromfile=file1, tofile=file2))

def schema_walk(left, right, lines, depth, col_width, indent):
    indent_str = ' ' * (depth * indent)
    # All keys in either left or right at this level
    left_keys = set(left.keys()) if isinstance(left, dict) else set()
    right_keys = set(right.keys()) if isinstance(right, dict) else set()
    all_keys = sorted(left_keys | right_keys)
    for key in all_keys:
        lval = left.get(key) if isinstance(left, dict) else None
        rval = right.get(key) if isinstance(right, dict) else None
        l_isdict = isinstance(lval, dict)
        r_isdict = isinstance(rval, dict)
        # If either side is a dict, recurse
        if l_isdict or r_isdict:
            left_head  = f"{indent_str}{key}:" if lval is not None else ""
            right_head = f"{indent_str}{key}:" if rval is not None else ""
            lines.append(f"{left_head:<{col_width}} | {right_head}")
            schema_walk(lval if l_isdict else {}, rval if r_isdict else {}, lines, depth + 1, col_width, indent)
        else:
            # Show as YAML key: value or blank
            ltext = f"{indent_str}{key}: {repr(lval)}" if lval is not None else ""
            rtext = f"{indent_str}{key}: {repr(rval)}" if rval is not None else ""
            lines.append(f"{ltext:<{col_width}} | {rtext}")

def format_yaml_side_by_side(schema1, schema2, file1, file2, indent=2, col_width=40):
    file1_base = os.path.basename(file1)
    file2_base = os.path.basename(file2)
    lines = []
    header = f"{file1_base:<{col_width}} | {file2_base}"
    lines.append(header)
    lines.append('-' * (col_width * 2 + 3))

    all_sections = sorted(set(schema1.keys()) | set(schema2.keys()))
    for section in all_sections:
        lsection = schema1.get(section)
        rsection = schema2.get(section)
        left_head = f"{section}:" if lsection is not None else ""
        right_head = f"{section}:" if rsection is not None else ""
        lines.append(f"{left_head:<{col_width}} | {right_head}")
        schema_walk(
            lsection if isinstance(lsection, dict) else {}, 
            rsection if isinstance(rsection, dict) else {},
            lines, 1, col_width, indent)
    return "\n".join(lines)

def run_schema_diff(file1, file2, diff_format="structured", output_file=None):
    schema1 = load_yaml(file1)
    schema2 = load_yaml(file2)
    alembic1 = schema1.get("alembic_version")
    alembic2 = schema2.get("alembic_version")
    if alembic1 == alembic2:
        msg = f"Schemas have identical alembic_version ({alembic1}); no differences to report."
        print(msg)
        if output_file:
            with open(output_file, "w") as f:
                f.write(msg + "\n")
        return

    diffs = diff_schemas(schema1, schema2)
    if diff_format == "unified":
        out = format_unified_diff(schema1, schema2, file1, file2)
    elif diff_format == "sidebyside":
        out = format_yaml_side_by_side(schema1, schema2, file1, file2)
    else:  # structured (default)
        out = format_structured_diff(diffs)

    print(out)
    if output_file:
        with open(output_file, "w") as f:
            f.write(out)

class ConsoleLogFilter(logging.Filter):
    def __init__(self, debug):
        super().__init__()
        self.debug = debug
    def filter(self, record):
        if self.debug:
            return True
        return record.levelno >= logging.CRITICAL

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate YAML configuration files against a schema.")
    parser.add_argument('--schema', help="YAML schema file")
    parser.add_argument('--config', help="YAML configuration file to validate")
    parser.add_argument('--rendered', help="Rendered Helm output: extract the db-preseed Secret and validate its custom_properties.yaml")
    parser.add_argument('--partial', action='store_true', help="Skip schema sections absent from the config (for partial preseed files)")
    parser.add_argument('--generate-example', action='store_true', help="Generate an example config file from the schema")
    parser.add_argument('--debug', '-d', action='store_true', help="Enable debug logging (very verbose)")
    parser.add_argument('--diff', nargs=2, metavar=('SCHEMA_OLD', 'SCHEMA_NEW'), help="Diff two schema files")
    parser.add_argument('--diff-format', choices=['structured','unified','sidebyside'], default='structured', help="Diff output format")
    parser.add_argument('--diff-output', help="Write diff to this file")

    args = parser.parse_args()

    if args.debug:
        console_handler.setLevel(logging.DEBUG)
        print("DEBUG MODE ENABLED (verbose logging)")
    else:
        console_handler.setLevel(logging.CRITICAL)

    if args.diff:
        run_schema_diff(args.diff[0], args.diff[1], diff_format=args.diff_format, output_file=args.diff_output)
        exit(0)

    for filt in console_handler.filters:
        console_handler.removeFilter(filt)
    console_handler.addFilter(ConsoleLogFilter(args.debug))

    schema = load_yaml(args.schema)

    if args.rendered:
        if not args.schema:
            parser.error("--schema is required with --rendered")
        with open(args.rendered) as f:
            docs = list(yaml.safe_load_all(f))
        preseed_doc = next(
            (d for d in docs if d and 'db-preseed' in d.get('metadata', {}).get('name', '')),
            None,
        )
        if not preseed_doc:
            print("ERROR: db-preseed Secret not found in rendered output", file=sys.stderr)
            sys.exit(1)
        content = preseed_doc.get('stringData', {}).get('custom_properties.yaml', '')
        config = yaml.safe_load(content)
        schema = load_yaml(args.schema)
        passed = validate(schema, config, debug=args.debug, partial=True)
        if passed:
            print("\n🎉 All top-level sections passed validation!")
        else:
            print("\n⚠️  One or more sections failed validation. See 'validation_errors.log' for details.")
    elif args.generate_example:
        generate_example(schema)
    elif args.config:
        config = load_yaml(args.config)

        schema_alembic = schema.get("alembic_version")
        config_alembic = config.get("alembic_version")
        if schema_alembic is not None:
            if config_alembic != schema_alembic:
                logger.error(
                    f"Alembic version mismatch: schema '{schema_alembic}' vs config '{config_alembic}'. Validation aborted."
                )
                print(f"\n❌ Alembic version mismatch: schema '{schema_alembic}' vs config '{config_alembic}'. Validation aborted.")
                sys.exit(2)
            else:
                logger.info(f"Alembic version matched: {schema_alembic}")

        passed = validate(schema, config, debug=args.debug, partial=args.partial)
        if passed:
            print("\n🎉 All top-level sections passed validation!")
        else:
            print("\n⚠️  One or more sections failed validation. See 'validation_errors.log' for details.")
    else:
        logger.error("No action specified. Provide --rendered, --config, or --generate-example.")
