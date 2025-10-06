#!/usr/bin/env bash
set -euo pipefail
# Convenience wrapper to clean up common blockers before `terraform destroy`

REGION="${REGION:-us-east-2}"
# Optional: pass specific SGs via ARGS; otherwise tries to infer "builder" and "vpce-ssm" by tag patterns
SGS="$@"

infer_sgs() {
  aws ec2 describe-security-groups --region "$REGION" \
    --filters Name=group-name,Values='*builder*','*vpce-ssm*','*vpce*ssm*' \
    --query 'SecurityGroups[].GroupId' --output text
}

if [[ -z "$SGS" ]]; then
  SGS="$(infer_sgs || true)"
fi

if [[ -z "$SGS" ]]; then
  echo "No candidate SGs found. Pass SG IDs explicitly, e.g.:"
  echo "  REGION=us-east-2 ./pre_destroy.sh sg-0123 sg-0456"
  exit 0
fi

echo "Region: $REGION"
echo "Candidate SGs: $SGS"

for SG in $SGS; do
  echo "== cleanup $SG =="
  "$(dirname "$0")/sg_cleanup.sh" --region "$REGION" --sg "$SG" || true
done

echo "Done. Now rerun: terraform destroy"
