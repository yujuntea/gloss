#!/usr/bin/env python3
"""Gloss 验收用本地 mock LLM（OpenAI 兼容 /chat/completions SSE）。
按用户消息中的模板标记返回对应 canned 响应，用于无真实 Key 的端到端验收。"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

WORD = """## idempotent
/ˌaɪdemˈpɒɪtənt/ /ˌaɪdəmˈpɒɪtənt/
**语境义**：（通用）指同一操作执行一次与执行多次的效果完全相同，结果不因重复调用而改变。
**词性与释义**
1. adj. 幂等的（数学与计算机术语）
2. adj. （化学）等幂的
**高频搭配**
- idempotent operation — 幂等操作
- idempotent request — 幂等请求
**例句**
1. A GET request is idempotent: calling it once or ten times returns the same result.（GET 请求是幂等的：调用一次或十次返回相同结果。）
2. The retry mechanism relies on idempotent writes to avoid duplicated orders.（重试机制依赖幂等写入以避免重复订单。）
**辨析**：与 consistent（一致性）不同，idempotent 强调"重复执行无副作用"；HTTP 规范中 GET/PUT/DELETE 幂等，POST 不幂等。"""

WORD_AT = """## operations
/ˌɒpəˈreɪʃənz/ /ˌɑːpəˈreɪʃənz/
**语境义**：在本图中指"幂等操作"中的 operations，即被讨论的操作本身。
**词性与释义**
1. n. 操作、运算（operation 的复数）
**高频搭配**
- idempotent operations — 幂等操作
**例句**
1. Idempotent operations ensure the same result.（幂等操作确保相同的结果。）
**辨析**：operation 泛指操作/运算，在此语境与 ensure 构成主谓关系。"""

SENTENCE = """**翻译**
虽然系统在部分节点失效时仍能继续运行，但这并不意味着它能够容忍任意数量的故障。
**结构拆解**
- 主干：this does not mean that it can tolerate an arbitrary number of failures
- While 引导的让步状语从句：While the system can continue to operate even when some of its nodes fail——"即使部分节点失效也能继续运行"，与主句形成让步关系
- even when 引导的从句：修饰从句内部，强调"在……发生时"
**难点**：not mean 否定的是 mean（并不意味着），而非直接否定 tolerate
**句中难词**
| 词/短语 | 音标 | 文中义 |
|---|---|---|
| tolerate | /ˈtɒləreɪt/ | 容忍、承受（故障） |
| arbitrary | /ˈɑːbɪtrəri/ | 任意（数量）的 |
| node | /nəʊd/ | 节点 |"""

PARAGRAPH = """**译文**
一致性模型决定了写入之后读取能看到什么。强一致性保证每次读取都能看到最新写入，但它带来的协调成本随规模增长。最终一致性放宽了这一要求：副本随时间收敛，在收敛窗口内不同读者可能看到不同的值。
**难词表**
| 词/短语 | 音标 | 文中义 | 原文例句 |
|---|---|---|---|
| consistency | /kənˈsɪstənsi/ | 一致性 | Consistency models determine what reads observe. |
| replica | /ˈreplɪkə/ | 副本 | replicas converge over time |
| converge | /kənˈvɜːdʒ/ | 收敛 | replicas converge over time |
| anomaly | /əˈnɒməli/ | 异常 | what kinds of anomalies users are willing to tolerate |"""

IMAGE = """**识别内容**
Idempotent operations ensure the same result.
**翻译与解释**
这张截图展示了一行英文："幂等操作确保结果相同"。它描述分布式系统的一个核心性质：无论操作执行多少次，结果都保持一致。这是接口设计与重试机制的基础。
**要点**
- idempotent（幂等的）：重复执行不改变结果
- 这是理解重试、去重与支付接口设计的基础概念"""

BATCH = """**译文**
分布式系统是协同工作的联网计算机集合，对外表现为一个内聚的整体。与单机不同，它必须面对部分失效：节点可能崩溃、链路可能丢包、时钟可能漂移（idempotency，幂等性）。
**难词表**
| 词/短语 | 音标 | 文中义 | 原文例句 |
|---|---|---|---|
| coherent | /kəʊˈhɪərənt/ | 内聚的 | appear as a single coherent system |
| partial failure | — | 部分失效 | must contend with partial failure |
| idempotency | /ˌaɪdemˈpɒɪtənsi/ | 幂等性 | The first fundamental property is idempotency |
| contending | /kənˈtendɪŋ/ | 应对 | must contend with partial failure |
**本批要点**
- 部分失效是分布式系统与单机的本质区别
- 幂等性让不可靠网络变得可推理
**本批术语**（若有）
| 术语 | 领域 | 解释 |
|---|---|---|
| idempotency key | 分布式系统 | 用于去重的请求标识，保证重试不重复执行 |"""

AGGREGATE = """**生词表**
| 词/短语 | 音标 | 文中义 | 原文例句 |
|---|---|---|---|
| idempotency | /ˌaɪdemˈpɒɪtənsi/ | 幂等性 | The first fundamental property is idempotency |
| consistency | /kənˈsɪstənsi/ | 一致性 | Strong consistency guarantees that every read sees the latest write |
| quorum | /ˈkwɔːrəm/ | 法定人数 | using quorum reads and writes |
| partition tolerance | — | 分区容错性 | The third property is partition tolerance |
| converge | /kənˈvɜːdʒ/ | 收敛 | replicas converge over time |
| anomaly | /əˈnɒməli/ | 异常 | what kinds of anomalies users are willing to tolerate |
| coherent | /kəʊˈhɪərənt/ | 内聚的 | appear as a single coherent system |
**术语表**
| 术语 | 领域 | 解释 |
|---|---|---|
| idempotency key | 分布式系统 | 用于去重的请求标识 |
| CAP theorem | 分布式理论 | 分区发生时在一致性与可用性间二选一 |
| Raft / Paxos | 共识算法 | 以强一致性复制日志并容忍节点失效 |
**逻辑解读**
- **主线**：以幂等性、一致性、分区容错三大性质为骨架，解释分布式系统设计取舍。
- **论证结构**：每节先给出性质定义，再以支付重试/读写延迟/分区切换等具体场景佐证，最后汇总到"读论文时应识别性质与代价"的方法论结论。
- **关键转折**：从"三大性质各自是什么"转向"组合起来如何解释现代基础设施"。
- **结论**：评估一篇分布式论文 = 识别它强化了哪一性质、牺牲了什么、该取舍是否匹配业务的真实失效模式。
- **背景补充**：CAP 定理出自 Eric Brewer（2000）；Raft 以可读性著称，Paxos 更早但更难懂。"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n))
        except Exception:
            body = {}
        msgs = body.get("messages", [])
        last = msgs[-1].get("content", "") if msgs else ""
        no_flush = False
        if isinstance(last, list):
            txt = last[0].get("text", "") if last else ""
            kind = "wordat" if "点击了坐标" in txt else "image"
        else:
            t = last
            no_flush = "NOFLUSH" in t  # 形态开关：仅最后一个 data 事件省略空行（真实服务器 bug 形态）
            t = t.replace("NOFLUSH", "")
            if "逐批材料" in t or ("【第" in t and "汇总" in t):
                kind = "aggregate"
            elif "长文分批" in t or "本批要点" in t:
                kind = "batch"
            elif "句子：" in t:
                kind = "sentence"
            elif "段落：" in t:
                kind = "paragraph"
            elif "查询：" in t:
                kind = "word"
            else:
                kind = "image"
        text = {"word": WORD, "wordat": WORD_AT, "sentence": SENTENCE, "paragraph": PARAGRAPH,
                "image": IMAGE, "batch": BATCH, "aggregate": AGGREGATE}.get(kind, WORD)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(b'data: {"choices":[{"delta":{"reasoning_content":"thinking..."}}]}\n\n')
        self.wfile.flush()
        time.sleep(0.15)
        n_chunks = (len(text) + 23) // 24
        for i in range(0, len(text), 24):
            part = text[i:i + 24]
            payload = json.dumps({"choices": [{"delta": {"content": part}}]}, ensure_ascii=False)
            idx = i // 24
            if no_flush and idx == n_chunks - 1:
                # 最后一个 data 事件省略空行，直接跟 [DONE]（真实服务器 bug 形态）
                self.wfile.write(f"data: {payload}\n".encode("utf-8"))
            else:
                self.wfile.write(f"data: {payload}\n\n".encode("utf-8"))
            self.wfile.flush()
            time.sleep(0.015)
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8787), Handler).serve_forever()
