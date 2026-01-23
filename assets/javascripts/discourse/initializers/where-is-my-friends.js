import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

export default {
  name: "where-is-my-friends",

  initialize() {
    withPluginApi("0.8.31", api => {
      // 添加导航栏项目
      api.addNavigationBarItem({
        name: "where-is-my-friends",
        displayName: i18n("where_is_my_friends.title"),
        href: "/where-is-my-friends",
        icon: "map-marker-alt"
      });
    });
  }
};

