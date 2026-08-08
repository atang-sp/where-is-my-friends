import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";

export default class FirstConnectionHomepage extends Service {
  @tracked activeRouteName = null;
  owner = null;

  claim(owner, routeName) {
    this.owner = owner;
    this.activeRouteName = routeName;
  }

  release(owner) {
    if (this.owner !== owner) {
      return;
    }

    this.owner = null;
    this.activeRouteName = null;
  }

  owns(routeName) {
    return Boolean(this.owner && this.activeRouteName === routeName);
  }
}
