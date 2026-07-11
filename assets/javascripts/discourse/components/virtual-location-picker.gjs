import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import {
  MapManager,
  providerLabel,
  resolveMapProvider,
} from "../lib/where-is-my-friends-maps";

export default class VirtualLocationPicker extends Component {
  @tracked latitude = 31.2304;
  @tracked longitude = 121.4737;
  @tracked loading = true;
  @tracked error = null;

  willDestroy() {
    this.mapManager?.destroy();
    this.latitude = null;
    this.longitude = null;
    super.willDestroy(...arguments);
  }

  get provider() {
    return resolveMapProvider(this.args.model.settings);
  }

  get providerName() {
    return providerLabel(this.provider);
  }

  @action
  async initializeMap(element) {
    this.mapManager = new MapManager(this.args.model.settings);
    this.mapManager.setSelectionHandler(({ latitude, longitude }) => {
      this.latitude = Number(latitude.toFixed(6));
      this.longitude = Number(longitude.toFixed(6));
    });

    try {
      await this.mapManager.init(element, {
        latitude: this.latitude,
        longitude: this.longitude,
      });
    } catch {
      this.error = i18n("where_is_my_friends.map_init_failed");
    } finally {
      this.loading = false;
    }
  }

  @action
  updateLatitude(event) {
    this.latitude = event.target.value;
    this.updateMarker();
  }

  @action
  updateLongitude(event) {
    this.longitude = event.target.value;
    this.updateMarker();
  }

  updateMarker() {
    const latitude = Number(this.latitude);
    const longitude = Number(this.longitude);
    if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
      this.mapManager?.updateMarker(latitude, longitude);
    }
  }

  @action
  confirm() {
    const latitude = Number(this.latitude);
    const longitude = Number(this.longitude);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      this.error = i18n("where_is_my_friends.invalid_coordinates");
      return;
    }

    this.args.model.onConfirm({ latitude, longitude });
    this.latitude = null;
    this.longitude = null;
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{i18n "where_is_my_friends.select_virtual_location"}}
      @closeModal={{@closeModal}}
      class="where-is-my-friends-map-modal"
    >
      <:body>
        <p>{{i18n "where_is_my_friends.virtual_location_instruction"}}</p>
        <p class="where-is-my-friends__provider" data-test-map-provider>
          {{this.providerName}}
        </p>
        <div
          class="where-is-my-friends__map"
          aria-label={{i18n "where_is_my_friends.map_aria_label"}}
          {{didInsert this.initializeMap}}
        ></div>
        {{#if this.loading}}
          <p role="status">{{i18n "where_is_my_friends.map_loading"}}</p>
        {{/if}}
        {{#if this.error}}
          <p class="alert alert-error">{{this.error}}</p>
        {{/if}}
        <div class="where-is-my-friends__coordinates">
          <label>
            {{i18n "where_is_my_friends.latitude"}}
            <input
              type="number"
              min="-90"
              max="90"
              step="0.000001"
              value={{this.latitude}}
              data-test-map-latitude
              {{on "input" this.updateLatitude}}
            />
          </label>
          <label>
            {{i18n "where_is_my_friends.longitude"}}
            <input
              type="number"
              min="-180"
              max="180"
              step="0.000001"
              value={{this.longitude}}
              data-test-map-longitude
              {{on "input" this.updateLongitude}}
            />
          </label>
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.confirm}}
          @label="where_is_my_friends.confirm_selection"
          class="btn-primary"
          data-test-confirm-map
        />
      </:footer>
    </DModal>
  </template>
}
