parse_yaml() {
    local yaml_file="$1"
    local prefix="$2"

    awk -v prefix="$prefix" '
    function escape(str) {
        gsub(/[^a-zA-Z0-9_]/, "_", str);
        gsub(/_+/, "_", str);
        gsub(/^_|_$/, "", str);
        return str;
    }

    BEGIN {
        FS=": *";
        depth = 0;
    }

    /^#/ || /^$/ { next }

    {
        gsub(/\r/, "");
        gsub(/[[:space:]]+$/, "");

        match($0, /^ */);
        indent = RLENGTH / 2;

        # Update stack for nesting
        if (indent < depth) {
            for (i = depth; i > indent; i--) {
                delete stack[i];
            }
        }
        depth = indent;

        if ($1 ~ /^ *- /) {
            # List item
            item = $1;
            gsub(/^ *- */, "", item);
            key = "";
            for (i = 0; i < depth; i++) {
                if (stack[i] != "") {
                    key = key (key == "" ? "" : "_") escape(stack[i]);
                }
            }
            array_index[key]++;
            printf("%s%s_%d=\"%s\"\n", prefix, key, array_index[key], item);
        } else {
            key_name = $1;
            stack[depth] = key_name;
            key = "";
            for (i = 0; i <= depth; i++) {
                if (stack[i] != "") {
                    key = key (key == "" ? "" : "_") escape(stack[i]);
                }
            }
            value = $0;
            sub(/^[^:]*:[[:space:]]*/, "", value);
            gsub(/^['\''"]|['\''"]$/, "", value);
            if (value != "") {
                printf("%s%s=\"%s\"\n", prefix, key, value);
            }
        }
    }' "$yaml_file"
}
