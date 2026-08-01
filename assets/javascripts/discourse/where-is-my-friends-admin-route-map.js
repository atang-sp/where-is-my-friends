export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",

  map() {
    this.route("where-is-my-friends-ai-providers", {
      path: "ai-providers",
    });
  },
};
