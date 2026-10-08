#!/usr/bin/env bash
# =============================================================================
# Trigger CI ด้วยมือ — ใช้แทน GitHub webhook (cluster นี้อยู่ intranet
# GitHub.com ส่ง event เข้าไม่ถึง จึงต้องสั่งจากด้านใน)
#
# ใช้งาน (จาก root ของ repo หลัง git push):
#   bash .tekton/trigger.sh            # สร้าง PipelineRun แล้วโชว์คำสั่งดู log
#   bash .tekton/trigger.sh --follow   # สร้างแล้ว stream log เลย
#
# ต้องมี: oc (login แล้ว), tkn, tkn-pac (PATH หรือ ~/bin)
# ตั้ง namespace ปลายทางได้ด้วย env: PIPELINE_NAMESPACE=<ns>
# =============================================================================
set -euo pipefail

FOLLOW="${1:-}"

TKNPAC="$(command -v tkn-pac || true)"
if [ -z "$TKNPAC" ] && [ -x "$HOME/bin/tkn-pac" ]; then
  TKNPAC="$HOME/bin/tkn-pac"
fi
if [ -z "$TKNPAC" ]; then
  echo "ไม่พบ tkn-pac — ติดตั้งจาก https://github.com/tektoncd/pipelines-as-code/releases" >&2
  exit 1
fi

REPO_URL="$(git remote get-url origin | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##')"
REVISION="$(git rev-parse HEAD)"
NS="${PIPELINE_NAMESPACE:-demo}"

echo "repo:     $REPO_URL"
echo "revision: $REVISION"
echo "ns:       $NS"
echo

RUN_JSON="$("$TKNPAC" resolve -f "$(dirname "$0")/push.yaml" -p repo_url="$REPO_URL" -p revision="$REVISION")"
CREATED="$(printf '%s\n' "$RUN_JSON" | oc create -n "$NS" -f - -o name)"
RUN_NAME="${CREATED##*/}"

echo
echo "PipelineRun '$RUN_NAME' created"
if [ "$FOLLOW" = "--follow" ]; then
  tkn pipelinerun logs "$RUN_NAME" -n "$NS" -f
else
  echo "ดู log: tkn pipelinerun logs -n $NS -f $RUN_NAME"
fi
