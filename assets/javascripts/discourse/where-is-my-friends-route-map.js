export default function () {
  this.route("where-is-my-friends");
  this.route("where-is-my-friends-interests", {
    path: "/where-is-my-friends/interests",
  });
  this.route("where-is-my-friends-flying-chess", {
    path: "/where-is-my-friends/flying-chess",
  });
}
