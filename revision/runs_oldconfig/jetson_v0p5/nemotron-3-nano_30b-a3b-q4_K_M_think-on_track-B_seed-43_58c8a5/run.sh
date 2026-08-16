#!/usr/bin/env bash
set -euo pipefail

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

for sample in "${samples[@]}"; do
   if [[ -f results/${sample}.bam ]]; then
      continue
   fi
   bwa mem -t 4 -R '@RG\\tID:${sample}\\tSM:${sample}\\tPL:ILLUMINA' data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz \
      | samtools view -@ 4 -b -o results/${sample}.bam
   samtools index results/${sample}.bam
   lofreq call -f data/ref/chrM.fa -o results/${sample}.vcf.gz -t 4 results/${sample}.bam
   tabix -p vcf results/${sample}.vcf.gz
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${samples[@]}"; do
   bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[%AF]\n' -s ${sample} results/${sample}.vcf.gz |
      awk -v s=${sample} '{
         split($4, a, /\[|]/);
         alt=a[1];
         af=a[2];
         print s "\t" $1 "\t" $2 "\t" $3 "\t" alt "\t" af
      }' >> results/collapsed.tsv
done