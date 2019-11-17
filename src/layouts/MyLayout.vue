<template>
  <q-layout view="lHh Lpr lFf">
    <q-header elevated>
      <!-- <q-toolbar> -->
        <!-- <q-btn
          flat
          dense
          round
          @click="leftDrawerOpen = !leftDrawerOpen"
          icon="menu"
          aria-label="Menu"
        /> -->
      <!-- </q-toolbar> -->
      <div class="q-px-lg q-pt-xl q-mb-md">
        <div class="text-h4 q-pb-lg q-pt-sm">Hi {{user.name}}!</div>
        <div class="text-subtitle">{{dt}}</div>
      </div>
      <q-img src="https://source.unsplash.com/random" class="header-image absolute-top headr-blr"></q-img>
    </q-header>

    <q-page-container>
      <keep-alive>
      <router-view />
      </keep-alive>
    </q-page-container>

  </q-layout>
</template>

<script>
import { date } from 'quasar'
export default {
  name: 'MyLayout',

  data () {
    return {
      user: {
        name: 'Mohan'
      },
      tab: 'mails',
      leftDrawerOpen: false,
      dt: ''
    }
  },
  mounted () {
    let timeStamp = Date.now()
    this.dt = date.formatDate(timeStamp, 'dddd, MMMM DD')
  }
}
</script>
