import Controller from "@ember/controller";

export default class WhereIsMyFriendsInterestsController extends Controller {
  queryParams = ["invite_to"];
  invite_to = null;
}
