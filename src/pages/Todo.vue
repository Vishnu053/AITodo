<template>
  <q-page>
    <div :style="'overflow: hidden auto; max-height:'+whgt+'px;'">
      <div class="q-pa-md row q-gutter-sm">
        <div class="col-12 blur-bg q-banner--dense text-subtitle1 text-white" style="background:radial-gradient(circle, rgba(255, 255, 255, 0.55) 0%, rgba(49, 49, 49, 0.28) 100%);">Today</div>
      <q-card v-for="(card,index) in cards" v-bind:key="index"
        class="my-card text-white col-12 blur-bg"
        style="background: radial-gradient(circle, rgba(165, 165, 165, 0.68) 0%, rgba(0, 0, 0, 0.28) 100%)"
      >
        <q-card-section>
          <div class="text-h6 q-pb-md q-pt-sm">{{card.title}}</div>
          <div class="text-subtitle2">by {{card.author}}</div>
        </q-card-section>
      </q-card>
    </div>
    </div>
    <q-img src="https://source.unsplash.com/random" class="header-image absolute-top "></q-img>
  </q-page>
</template>

<script>
export default {
  data () {
    return {
      whgt: window.innerHeight - 168,
      cards: [
        {
          title: 'Our Changing Planets',
          author: 'Mohan'
        },
        {
          title: 'Our Changing Planets',
          author: 'Mohan'
        },
        {
          title: 'Our Changing Planets',
          author: 'Mohan'
        }
      ]
    }
  }
}
</script>
