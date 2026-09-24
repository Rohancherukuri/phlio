"""Phlio Social domain — feed, posts, likes, comments.

Scoped for this build stage to text/image posts with likes and comments.
Stories, DMs, short-form video and the richer file-sharing matrix described
in the architecture document (section 2) are left for a later pass — the
`Post` entity's `media` field is shaped so those can be added without a
breaking change.
"""
