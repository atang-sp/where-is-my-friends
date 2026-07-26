import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class WhereIsMyFriendsInterestsRoute extends DiscourseRoute {
  model() {
    return ajax("/where-is-my-friends/recommendations.json");
  }
}
