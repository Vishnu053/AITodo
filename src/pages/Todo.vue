<template>
  <q-page>
    <div :style="'overflow: hidden auto; max-height:'+whgt+'px;'">
      <div class="q-gutter-sm">
        <div class="col-12 blur-bg q-banner--dense text-subtitle1 text-white" style="background:radial-gradient(circle, rgba(255, 255, 255, 0.55) 0%, rgba(49, 49, 49, 0.28) 100%);">Recent</div>
        <div class="row q-pl-xs q-pr-xs">
      <q-card clickable v-ripple v-for="(card,index) in cards" v-bind:key="index"
        class="my-card text-white col-6 blur-bg"
        style="background: radial-gradient(circle, rgba(165, 165, 165, 0.68) 0%, rgba(0, 0, 0, 0.28) 100%)"
        @click="openNote(card)"
      >
        <q-card-section>
          <div class="text-h6 q-pb-md q-pt-sm">{{card.title}}</div>
          <div class="text-subtitle2">by {{card.author}}</div>
        </q-card-section>
      </q-card>
      </div>
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
          title: 'As I Dream.',
          author: 'Mohan',
          content: 'Lorem ipsum dolor sit amet consectetur adipisicing elit. Ut porro ab reprehenderit repellendus aliquam delectus hic molestiae odit, iste voluptatem id, cumque omnis rem veritatis tenetur animi vel consequuntur perferendis!'
        },
        {
          title: 'These birds..',
          author: 'Vishnu',
          content: 'Lorem ipsum dolor sit amet consectetur adipisicing elit. Ut porro ab reprehenderit repellendus aliquam delectus hic molestiae odit, iste voluptatem id, cumque omnis rem veritatis tenetur animi vel consequuntur perferendis!'
        },
        {
          title: 'A Journey to the hills.',
          author: 'Kala',
          content: 'Lorem ipsum dolor sit amet consectetur adipisicing elit. Ut porro ab reprehenderit repellendus aliquam delectus hic molestiae odit, iste voluptatem id, cumque omnis rem veritatis tenetur animi vel consequuntur perferendis!'
        }
      ]
    }
  },
  methods: {
    openNote (note) {
      localStorage.setItem('tmpnt', JSON.stringify(note))
      this.$router.push('/note')
    }
  }
}
</script>
