<script type="text/discourse-plugin" version="0.8">
  /* 调整回复按钮文字 */
  api.replaceIcon("reply", "comment-dots");

  api.onPageChange(() => {
    /* ---------- 楼内回复按钮：回复本楼 ---------- */
    document
      .querySelectorAll(".topic-post .reply:not(.reply-labeled)")
      .forEach((replyBtn) => {
        // 排除页底工具栏按钮
        if (replyBtn.closest("#topic-footer-buttons")) return;

        replyBtn.classList.add("reply-labeled");
        const span       = document.createElement("span");
        span.className   = "reply-btn-label";
        span.textContent = "回复本楼";
        replyBtn.appendChild(span);
      });

    /* ---------- 主题回复按钮：回复主题 ---------- */
    const topicReplyBtn = document.querySelector(
      "#topic-footer-buttons .btn.create:not(.reply-labeled)"
    );
    if (topicReplyBtn) {
      topicReplyBtn.classList.add("reply-labeled");
      const span       = document.createElement("span");
      span.className   = "reply-btn-label";
      span.textContent = "回复主题";
      topicReplyBtn.appendChild(span);
    }

    /* ---------- 注入样式（仅插入一次） ---------- */
    if (!document.querySelector("#reply-label-style")) {
      const style = document.createElement("style");
      style.id = "reply-label-style";
      style.innerHTML = `
        .reply-btn-label {
          margin-left: 0.25em;
          font-size: 0.75rem;
        }
      `;
      document.head.appendChild(style);
    }
  });
</script>