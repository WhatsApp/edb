/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* eslint-disable */

import React from 'react';
import clsx from 'clsx';
import styles from './HomepageFeatures.module.css';

const FeatureList = [
  {
    title: 'No timeouts',
    icon: '⏰',
    description: (
      <>
        EDB freezes (or rather it gives the illusion of freezing) the Erlang VM, to prevent timeouts during a debugging session.
      </>
    ),
  },
  {
    title: 'Easy to Use',
    icon: '😌',
    description: (
      <>
        EDB provides a simple and intuitive step-by-step debugging experience.
      </>
    ),
  },
  {
    title: 'DAP Included',
    icon: '🔋',
    description: (
      <>
        By shipping with a fully featured <a href='https://microsoft.github.io/debug-adapter-protocol/' target='_blank'>DAP adapter</a>, ELP easily integrates into your IDE of choice.
      </>
    ),
  },
];

function Feature({icon, title, description}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center" style={{fontSize: '400%'}}>
        {icon}
      </div>
      <div className="text--center padding-horiz--md">
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
