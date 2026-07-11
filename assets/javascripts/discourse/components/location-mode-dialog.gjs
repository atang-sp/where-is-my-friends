import Component from "@glimmer/component";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";

export default class LocationModeDialog extends Component {
  @action
  useGps() {
    this.args.closeModal();
    this.args.model.onGps();
  }

  @action
  useMap() {
    this.args.closeModal();
    this.args.model.onMap();
  }

  <template>
    <DModal
      @title={{i18n "where_is_my_friends.advanced_location_title"}}
      @closeModal={{@closeModal}}
      class="where-is-my-friends-location-modal"
    >
      <:body>
        <p>{{i18n "where_is_my_friends.advanced_location_description"}}</p>
        <div class="where-is-my-friends__mode-options">
          <DButton
            @action={{this.useGps}}
            @icon="location-crosshairs"
            @label="where_is_my_friends.use_gps"
            class="btn-primary"
            data-test-use-gps
          />
          <p>{{i18n "where_is_my_friends.use_gps_description"}}</p>
          <DButton
            @action={{this.useMap}}
            @icon="map"
            @label="where_is_my_friends.choose_on_map"
            data-test-use-map
          />
          <p>{{i18n "where_is_my_friends.choose_on_map_description"}}</p>
        </div>
      </:body>
    </DModal>
  </template>
}
