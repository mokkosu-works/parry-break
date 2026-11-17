"""YouTube Analytics の取得 → 日次の行 (読み取り専用。標準ライブラリだけ)。

鍵は環境変数で渡す (Actions の secret): YT_CLIENT_ID / YT_CLIENT_SECRET / YT_REFRESH_TOKEN。
使う権限は yt-analytics.readonly と youtube.readonly だけ。refresh token の作り方は docs/analytics-pipeline.md の §5。
"""
import datetime, json, os, sys, urllib.error, urllib.parse, urllib.request

TOKEN_URI = "https://oauth2.googleapis.com/token"
ANALYTICS = "https://youtubeanalytics.googleapis.com/v2/reports"
DATA_API = "https://www.googleapis.com/youtube/v3"
METRICS = ["views", "engagedViews", "estimatedMinutesWatched", "likes", "shares", "comments",
           "subscribersGained", "averageViewDuration", "averageViewPercentage"]
RETENTION_POINTS = (0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 1.00)  # 経過時間の割合ごとの audienceWatchRatio (28 日の窓の写し)
MIN_VIEWS_FOR_RETENTION = 20


class ApiError(RuntimeError):
    pass


def http_json(url, data=None, headers=None):
    req = urllib.request.Request(url, urllib.parse.urlencode(data).encode() if data else None, headers=headers or {},
                                 method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        # 応答の本文は、鍵や ID を含みうるので、ログには状態コードだけ出す
        raise ApiError(f"{url.split('?')[0]} が HTTP {e.code}") from None


def access_token(env=os.environ):
    for k in ("YT_CLIENT_ID", "YT_CLIENT_SECRET", "YT_REFRESH_TOKEN"):
        if not env.get(k):
            raise ApiError(f"{k} が未設定")
    return http_json(TOKEN_URI, {"client_id": env["YT_CLIENT_ID"], "client_secret": env["YT_CLIENT_SECRET"],
                                 "refresh_token": env["YT_REFRESH_TOKEN"], "grant_type": "refresh_token"})["access_token"]


def api_get(url, params, tok):
    return http_json(url + "?" + urllib.parse.urlencode(params), headers={"Authorization": f"Bearer {tok}"})


def table_rows(source, entity, table, date_col="day", prefix=""):
    """Analytics API の表 ({columnHeaders, rows}) を、日次の行にする。date_col 以外の列が、指標。"""
    cols = [h["name"] for h in table.get("columnHeaders", [])]
    if date_col not in cols:
        return []
    di = cols.index(date_col)
    out = []
    for row in table.get("rows") or []:
        for i, c in enumerate(cols):
            if i != di and isinstance(row[i], (int, float)) and not isinstance(row[i], bool):
                out.append({"source": source, "metric": prefix + c, "entity": entity, "date": row[di], "value": row[i]})
    return out


def retention_rows(entity, table, snapshot_date):
    """維持率の曲線 (elapsedVideoTimeRatio 別) から、決めた地点の値を、取得日つきの行にする (その日の 28 日の窓の写し)。"""
    cols = [h["name"] for h in table.get("columnHeaders", [])]
    if "elapsedVideoTimeRatio" not in cols or "audienceWatchRatio" not in cols:
        return []
    ri, vi = cols.index("elapsedVideoTimeRatio"), cols.index("audienceWatchRatio")
    by = {round(r[ri], 2): r[vi] for r in table.get("rows") or []}
    return [{"source": "youtube", "metric": f"retention_r{int(p * 100):03d}", "entity": entity, "date": snapshot_date, "value": by[round(p, 2)]}
            for p in RETENTION_POINTS if round(p, 2) in by]


def collect(start, end, today, get=api_get, token=None):
    """start〜end (日付) の日次の行と、動画のメタ情報 ({動画ID: {title, published_jst}}) を返す。"""
    tok = token or access_token()
    p = {"ids": "channel==MINE", "startDate": start.isoformat(), "endDate": end.isoformat()}
    rows = table_rows("youtube", "channel", get(ANALYTICS, {**p, "dimensions": "day", "metrics": ",".join(METRICS), "sort": "day"}, tok))
    vids = get(ANALYTICS, {**p, "dimensions": "video", "metrics": "views", "sort": "-views", "maxResults": 200}, tok)
    ids = [(r[0], r[1]) for r in vids.get("rows") or []]
    for vid, _ in ids:
        t = get(ANALYTICS, {**p, "dimensions": "day", "metrics": ",".join(METRICS), "filters": f"video=={vid}", "sort": "day"}, tok)
        rows += table_rows("youtube", vid, t)
    # 維持率は、28 日の窓で取る (数字が少ない動画は、曲線が当てにならないので除く)
    w28 = {**p, "startDate": (end - datetime.timedelta(days=27)).isoformat()}
    for vid, _ in ids:
        v28 = get(ANALYTICS, {**w28, "dimensions": "video", "metrics": "views", "filters": f"video=={vid}"}, tok)
        views = (v28.get("rows") or [[None, 0]])[0][1]
        if views >= MIN_VIEWS_FOR_RETENTION:
            c = get(ANALYTICS, {**w28, "dimensions": "elapsedVideoTimeRatio", "metrics": "audienceWatchRatio",
                                "filters": f"video=={vid}", "sort": "elapsedVideoTimeRatio"}, tok)
            rows += retention_rows(vid, c, today.isoformat())
    meta = {}
    all_ids = [v for v, _ in ids]
    for i in range(0, len(all_ids), 50):
        r = get(DATA_API + "/videos", {"part": "snippet", "id": ",".join(all_ids[i:i + 50])}, tok)
        for it in r.get("items", []):
            pub = datetime.datetime.fromisoformat(it["snippet"]["publishedAt"].replace("Z", "+00:00"))
            meta[it["id"]] = {"title": it["snippet"]["title"].strip(),
                              "published_jst": (pub + datetime.timedelta(hours=9)).date().isoformat()}
    return rows, meta
