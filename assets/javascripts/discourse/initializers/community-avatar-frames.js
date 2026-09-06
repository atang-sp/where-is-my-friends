import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "where-is-my-friends-avatar-frames",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (siteSettings?.where_is_my_friends_avatar_frames_enabled === false) {
      return;
    }

    withPluginApi((api) => {
      if (typeof api.customUserAvatarClasses !== "function") {
        return;
      }

      api.customUserAvatarClasses((user) => {
        if (!user) {
          return [];
        }
        const raw =
          user.community_level?.level ||
          (typeof user.community_level === "number"
            ? user.community_level
            : null);
        const level = Number(raw);
        if (level >= 2 && level <= 8) {
          return [`community-avatar-level-${level}`];
        }
        return [];
      });
    });
  },
};
