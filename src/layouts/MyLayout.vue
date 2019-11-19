<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <keep-alive>
      <router-view />
      </keep-alive>
    </q-page-container>

  </q-layout>
</template>

<script>
export default {
  name: 'MyLayout',

  data () {
    return {
      tab: 'mails'
    }
  }
}
</script>
