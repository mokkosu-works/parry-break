#!/usr/bin/env bash
# dev 向けの PR を、次がすべてそろっていれば squash でマージする。どれかが欠けていれば、理由を出して何もしない。
#   - 人 (OWNER / MEMBER / COLLABORATOR) が、いまの先頭のコミットを Approve している
#   - pr.yml の check・e2e・review が、いまの先頭のコミットで成功している
#   - hold / needs-fix のラベルが付いていない
# pr.yml (チェックが終わったとき) と merge.yml (人が Approve したとき) から呼ぶ。順番はどちらが先でもよい。
#
#   GH_TOKEN=... GITHUB_REPOSITORY=owner/repo merge-if-approved.sh <PR 番号>
set -euo pipefail

pr="$1"
repo="$GITHUB_REPOSITORY"

info=$(gh pr view "$pr" -R "$repo" --json baseRefName,headRefOid,isDraft,state,labels)
base=$(jq -r .baseRefName <<<"$info")
head=$(jq -r .headRefOid <<<"$info")

skip() {
  echo "::notice::#$pr はマージしない: $1"
  exit 0
}

[ "$(jq -r .state <<<"$info")" = OPEN ] || skip "開いていない"
[ "$base" = dev ] || skip "dev 向けではない ($base)。main 向けは人が手でマージする"
[ "$(jq -r .isDraft <<<"$info")" = false ] || skip "下書き"

labels=$(jq -r '[.labels[].name] | join(" ")' <<<"$info")
if grep -qwE 'hold|needs-fix' <<<"$labels"; then
  skip "ラベル ($labels) が付いている"
fi

# 人ごとの最後のレビューが、先頭のコミットへの Approve か
approvers=$(gh api --paginate "repos/$repo/pulls/$pr/reviews" | jq -rs --arg head "$head" '
  add
  | map(select(.user.type == "User" and (.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))))
  | map(select(.state != "COMMENTED"))
  | group_by(.user.login)
  | map(max_by(.submitted_at))
  | map(select(.state == "APPROVED" and .commit_id == $head) | .user.login)
  | join(" ")')
[ -n "$approvers" ] || skip "先頭のコミット (${head:0:7}) を Approve した人がいない。push のあとは Approve し直す"

# pr.yml のジョブの結果 (同じ名前が何度も走っていれば、最後のもの)
runs=$(gh api --paginate "repos/$repo/commits/$head/check-runs" | jq -s 'map(.check_runs) | add')
for name in "check / check" e2e review; do
  conclusion=$(jq -r --arg n "$name" 'map(select(.name == $n)) | max_by(.started_at) | .conclusion // "なし"' <<<"$runs")
  [ "$conclusion" = success ] || skip "$name が成功していない ($conclusion)。終われば自動でマージする"
done

echo "Approve: $approvers"
# 確かめたあとに push されていたらマージしない (その push の実行に任せる)
gh pr merge "$pr" -R "$repo" --squash --delete-branch --match-head-commit "$head"
