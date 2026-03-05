#!/bin/bash
# =============================================================
#  rankmath-connect-bulk.sh
#  Bulk Connect Account — Rank Math SEO (Free Plan)
#  Copy registration data จากเว็บที่ connect แล้วไปทุกเว็บ
# =============================================================

VERSION="1.0.7"

MAX_JOBS=5
WP_TIMEOUT=30

# ─── ข้อมูล Registration จากเว็บที่ connect แล้ว ────────────
RM_USERNAME="ufavisionseoteam"
RM_EMAIL="ufavisionseoteam@gmail.com"
RM_API_KEY="03cefb18bb49a91d3c619d2906b43db8"
RM_PLAN="free"
# ─── ข้อมูล Account เก่า (สำหรับ deactivate จาก rankmath.com) ──
RM_OLD_USERNAME="ufasonicseoteam"
RM_OLD_API_KEY="e3f2de5cccb84e62c9e4df85100e87b8"
# ─────────────────────────────────────────────────────────────

LOG_FILE="/var/log/rankmath-connect.log"
LOG_PASS="/var/log/rankmath-connect-pass.log"
LOG_FAIL="/var/log/rankmath-connect-fail.log"
LOG_ALREADY="/var/log/rankmath-connect-already.log"
LOG_OVERWRITE="/var/log/rankmath-connect-overwrite.log"
LOG_NOPLUGIN="/var/log/rankmath-connect-noplugin.log"
LOG_SKIP="/var/log/rankmath-connect-skip.log"
LOCK_FILE="${LOG_FILE}.lock"
RESULT_DIR="/tmp/rankmath-connect-$$"
mkdir -p "$RESULT_DIR"

log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$1"
    ( flock 200; echo "[$ts] $1" >> "$LOG_FILE" ) 200>"$LOCK_FILE"
}

cleanup() {
    wait
    rm -rf "$RESULT_DIR"
    rm -f "$LOCK_FILE" \
        "${LOG_FILE}.pass.lock" "${LOG_FILE}.fail.lock" \
        "${LOG_FILE}.already.lock" "${LOG_FILE}.overwrite.lock" \
        "${LOG_FILE}.noplugin.lock" "${LOG_FILE}.skip.lock"
}
trap cleanup EXIT

# ─── ตรวจ WP-CLI ─────────────────────────────────────────────
if ! command -v wp &>/dev/null; then
    log "❌ ERROR: ไม่พบ WP-CLI — https://wp-cli.org"
    exit 1
fi

# ─── ล้าง log ────────────────────────────────────────────────
> "$LOG_FILE"; > "$LOG_PASS"; > "$LOG_FAIL"
> "$LOG_ALREADY"; > "$LOG_OVERWRITE"; > "$LOG_NOPLUGIN"; > "$LOG_SKIP"

START_TIME=$(date +%s)
log "======================================"
log " BULK RANK MATH CONNECT (FREE PLAN)"
log " Version  : v$VERSION"
log " เริ่มเวลา : $(date '+%Y-%m-%d %H:%M:%S')"
log " Account  : $RM_EMAIL | plan=$RM_PLAN"
log " Jobs     : $MAX_JOBS"
log "======================================"

# ─── ค้นหา WordPress ทุกเว็บ ─────────────────────────────────
declare -A _SEEN
DIRS=()

if [[ -f /etc/trueuserdomains ]]; then
    while IFS=' ' read -r _dom _usr _rest; do
        _usr="${_usr%:}"
        [[ -z "$_usr" ]] && continue
        _uhome=$(getent passwd "$_usr" 2>/dev/null | cut -d: -f6)
        [[ -d "$_uhome" ]] || continue
        while IFS= read -r -d '' _wpc; do
            _d="$(dirname "$_wpc")/"
            [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
        done < <(find "$_uhome" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
    done < /etc/trueuserdomains
fi

for _base in /home /home2 /home3 /home4 /home5 /usr/home; do
    [[ -d "$_base" ]] || continue
    while IFS= read -r -d '' _wpc; do
        _d="$(dirname "$_wpc")/"
        [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
    done < <(find "$_base" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
done

TOTAL=${#DIRS[@]}
log "พบ WordPress : $TOTAL เว็บ"
log "======================================"

# ─── process แต่ละเว็บ ───────────────────────────────────────
process_site() {
    local dir="$1"
    local COUNT="$2"
    local TOTAL="$3"
    local SITE UNIQ
    SITE=$(echo "$dir" | sed 's|/home[0-9]*/||;s|/$||')
    UNIQ="${BASHPID}_$(date +%s%N)"
    local LABEL="[$COUNT/$TOTAL] $SITE"

    [[ "$dir" =~ /public_html/$ ]] && return

    _log() {
        local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$1"
        ( flock 200; echo "[$ts] $1" >> "$LOG_FILE" ) 200>"$LOCK_FILE"
    }
    _log_r() {
        local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
        case "$1" in
            pass)     ( flock 201; echo "[$ts] $2" >> "$LOG_PASS"      ) 201>"${LOG_FILE}.pass.lock" ;;
            fail)     ( flock 202; echo "[$ts] $2" >> "$LOG_FAIL"      ) 202>"${LOG_FILE}.fail.lock" ;;
            already)  ( flock 203; echo "[$ts] $2" >> "$LOG_ALREADY"   ) 203>"${LOG_FILE}.already.lock" ;;
            overwrite)( flock 206; echo "[$ts] $2" >> "$LOG_OVERWRITE" ) 206>"${LOG_FILE}.overwrite.lock" ;;
            noplugin) ( flock 204; echo "[$ts] $2" >> "$LOG_NOPLUGIN"  ) 204>"${LOG_FILE}.noplugin.lock" ;;
            skip)     ( flock 205; echo "[$ts] $2" >> "$LOG_SKIP"      ) 205>"${LOG_FILE}.skip.lock" ;;
        esac
    }

    local U="$RM_USERNAME"
    local E="$RM_EMAIL"
    local K="$RM_API_KEY"
    local P="$RM_PLAN"
    local OLD_U="$RM_OLD_USERNAME"
    local OLD_K="$RM_OLD_API_KEY"

    EVAL_OUT=$(timeout "$WP_TIMEOUT" wp --path="$dir" eval '
        // ── 1. ตรวจ Plugin ───────────────────────────────────
        $active = false;
        foreach (["seo-by-rank-math/rank-math.php", "rank-math-seo/rank-math.php"] as $f) {
            if (is_plugin_active($f)) { $active = true; break; }
        }
        if (!$active) { echo "STATUS:NOPLUGIN"; return; }

        // ── 2. ตรวจว่า connect แล้วหรือยัง ──────────────────
        $existing = RankMath\Admin\Admin_Helper::get_registration_data();
        if ($existing && !empty($existing["api_key"])) {
            $current_user = $existing["username"] ?? "";
            // ถ้าเป็น account เดียวกัน → ALREADY ข้ามไปเลย
            if ($current_user === "'"$U"'") {
                printf("STATUS:ALREADY\tUSER:%s\tPLAN:%s",
                    $existing["username"] ?? "?",
                    $existing["plan"]     ?? "?"
                );
                return;
            }
            // ถ้าเป็น account อื่น → OVERWRITE ล้างแล้ว inject ใหม่
            printf("STATUS:OVERWRITE\tOLD_USER:%s\t", $current_user);

            // ยิง deactivateSite ไปบอก rankmath.com ให้ถอด site จาก account เก่า
            $old_api_key = ($current_user === "'"$OLD_U"'") ? "'"$OLD_K"'" : $existing["api_key"];
            wp_remote_post(
                "https://rankmath.com/wp-json/rankmath/v1/deactivateSite",
                [
                    "body"    => wp_json_encode([
                        "username" => $current_user,
                        "api_key"  => $old_api_key,
                        "site_url" => esc_url(home_url()),
                    ]),
                    "headers" => ["Content-Type" => "application/json"],
                    "timeout" => 15,
                ]
            );

            RankMath\Admin\Admin_Helper::get_registration_data(false);
        }

        // ── 3. Inject registration data ──────────────────────
        $site_url = get_option("siteurl");

        // flush cache ก่อน เพื่อล้างค่าเก่าที่อาจ cache ไว้
        wp_cache_flush();

        $data = [
            "username"  => "'"$U"'",
            "email"     => "'"$E"'",
            "api_key"   => "'"$K"'",
            "plan"      => "'"$P"'",
            "connected" => true,
            "site_url"  => $site_url,
        ];

        // เรียก Admin_Helper ให้จัดการ encrypt + บันทึก DB เอง
        $result = RankMath\Admin\Admin_Helper::get_registration_data($data);

        // flush cache หลังบันทึก เพื่อให้ plugin อ่านค่าใหม่ทันที
        wp_cache_flush();
        wp_cache_delete("rank_math_connect_data", "options");
        delete_transient("rank_math_connect_data");

        // flush LiteSpeed Cache ถ้ามี
        if (class_exists("LiteSpeed\Purge")) {
            LiteSpeed\Purge::purge_all();
        } elseif (function_exists("litespeed_purge_all")) {
            litespeed_purge_all();
        }
        if (class_exists("LiteSpeed_Cache_API")) {
            LiteSpeed_Cache_API::purge_all();
        }

        // ── 4. Verify ─────────────────────────────────────────
        $verify = RankMath\Admin\Admin_Helper::get_registration_data();
        $ok = ($verify && !empty($verify["api_key"]) && $verify["api_key"] === "'"$K"'") ? "1" : "0";

        printf("STATUS:DONE\tSITE:%s\tSAVED:%s", $site_url, $ok);
    ' --allow-root 2>/dev/null)

    # flush Redis cache ผ่าน WP-CLI ด้านนอกด้วย (กรณี wp_cache_flush ด้านในไม่พอ)
    timeout 10 wp --path="$dir" cache flush --allow-root &>/dev/null || true

    # flush LiteSpeed Cache ผ่าน WP-CLI (ถ้ามี plugin)
    timeout 10 wp --path="$dir" litespeed-purge all --allow-root &>/dev/null || true

    local STATUS
    STATUS=$(echo "$EVAL_OUT" | grep -oP '(?<=STATUS:)\w+')

    case "$STATUS" in
        ALREADY)
            local AU AP
            AU=$(echo "$EVAL_OUT" | grep -oP '(?<=USER:)[^\t]*')
            AP=$(echo "$EVAL_OUT" | grep -oP '(?<=PLAN:)[^\t]*')
            _log  "✔️  ALREADY: $LABEL | user=$AU | plan=$AP"
            _log_r already "$SITE | user=$AU | plan=$AP"
            touch "${RESULT_DIR}/already_${UNIQ}"
            ;;
        OVERWRITE)
            local OLD_U DU DS
            OLD_U=$(echo "$EVAL_OUT" | grep -oP '(?<=OLD_USER:)[^\t ]*')
            DU=$(echo "$EVAL_OUT"    | grep -oP '(?<=SITE:)[^\t ]*')
            DS=$(echo "$EVAL_OUT"    | grep -oP '(?<=SAVED:)\d+')
            if echo "$EVAL_OUT" | grep -q "SAVED:1"; then
                _log  "🔄 OVERWRITE: $LABEL | old=$OLD_U → new=$RM_USERNAME | site=$DU"
                _log_r overwrite "$SITE | old_user=$OLD_U → new_user=$RM_USERNAME | site=$DU"
                touch "${RESULT_DIR}/pass_${UNIQ}"
            else
                _log  "❌ FAIL (overwrite verify ล้มเหลว): $LABEL | old=$OLD_U"
                _log_r fail "$SITE | overwrite fail | old_user=$OLD_U"
                touch "${RESULT_DIR}/fail_${UNIQ}"
            fi
            ;;
        NOPLUGIN)
            _log  "⏭  SKIP (ไม่มี Rank Math): $LABEL"
            _log_r noplugin "$SITE"
            touch "${RESULT_DIR}/noplugin_${UNIQ}"
            ;;
        DONE)
            local DS DU
            DU=$(echo "$EVAL_OUT" | grep -oP '(?<=SITE:)[^\t]*')
            DS=$(echo "$EVAL_OUT" | grep -oP '(?<=SAVED:)\d+')
            if [[ "$DS" == "1" ]]; then
                _log  "✅ PASS: $LABEL | site=$DU"
                _log_r pass "$SITE | site=$DU"
                touch "${RESULT_DIR}/pass_${UNIQ}"
            else
                _log  "❌ FAIL (verify ล้มเหลว): $LABEL"
                _log_r fail "$SITE | บันทึกสำเร็จแต่ verify ไม่ผ่าน"
                touch "${RESULT_DIR}/fail_${UNIQ}"
            fi
            ;;
        *)
            _log  "❌ FAIL (wp error/timeout): $LABEL | ${EVAL_OUT:0:100}"
            _log_r fail "$SITE | ${EVAL_OUT:0:100}"
            touch "${RESULT_DIR}/fail_${UNIQ}"
            ;;
    esac
}

export -f process_site
export LOG_FILE LOCK_FILE LOG_PASS LOG_FAIL LOG_ALREADY LOG_OVERWRITE LOG_NOPLUGIN LOG_SKIP
export RESULT_DIR WP_TIMEOUT RM_USERNAME RM_EMAIL RM_API_KEY RM_PLAN RM_OLD_USERNAME RM_OLD_API_KEY

# ─── รัน parallel ────────────────────────────────────────────
declare -a PIDS=()
COUNT=0
for dir in "${DIRS[@]}"; do
    COUNT=$(( COUNT + 1 ))
    process_site "$dir" "$COUNT" "$TOTAL" &
    PIDS+=($!)
    if (( ${#PIDS[@]} >= MAX_JOBS )); then
        wait "${PIDS[0]}"
        PIDS=("${PIDS[@]:1}")
    fi
done
for pid in "${PIDS[@]}"; do wait "$pid"; done

# ─── สรุป ────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
SUCCESS=$(  find "$RESULT_DIR" -name "pass_*"     2>/dev/null | wc -l)
FAILED=$(   find "$RESULT_DIR" -name "fail_*"     2>/dev/null | wc -l)
ALREADY=$(  find "$RESULT_DIR" -name "already_*"  2>/dev/null | wc -l)
NOPLUGIN=$( find "$RESULT_DIR" -name "noplugin_*" 2>/dev/null | wc -l)
OVERWRITE=$(grep -c "OVERWRITE" "$LOG_OVERWRITE" 2>/dev/null || echo 0)

log "======================================"
log " สรุปผลรวม"
log " รวมทั้งหมด              : $TOTAL เว็บ"
log " ✅ Pass (inject ใหม่)   : $SUCCESS เว็บ"
log " ✔️  Already (ufavision)  : $ALREADY เว็บ  (ข้ามแล้ว)"
log " 🔄 Overwrite (account อื่น) : $OVERWRITE เว็บ (เปลี่ยนเป็น ufavision แล้ว)"
log " ❌ Fail                  : $FAILED เว็บ"
log " ⏭  No Plugin             : $NOPLUGIN เว็บ"
log " เวลาที่ใช้               : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
log "======================================"
log " ✅ Pass      : $LOG_PASS"
log " ✔️  Already   : $LOG_ALREADY"
log " 🔄 Overwrite : $LOG_OVERWRITE"
log " ❌ Fail      : $LOG_FAIL"
log " ⏭  Skip      : $LOG_NOPLUGIN"
log "======================================"
