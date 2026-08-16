#!/usr/bin/env bash
set -euo pipefail
THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.amb ]; then
  bwa index data/ref/chrM.fa
fi

# Process each sample
for sample in "${samples[@]}"; do
  # Skip if all final outputs already exist
  if [ -f results/${sample}.vcf.gz.tbi ] && \
     [ -f results/${sample}.bam.bai ] && \
     [ -f results/${sample}.bam ] && \
     [ -f results/${sample}.vcf.gz ]; then
    continue
  fi

  # Align with bwa mem and sort to BAM
  if [ ! -f results/${sample}.bam ]; then
    bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
      samtools sort -@ $THREADS -o results/${sample}.bam
  fi

  # Index BAM
  if [ ! -f results/${sample}.bam.bai ]; then
    samtools index -@ $THREADS results/${sample}.bam
  fi

  # Variant calling with lofreq
  if [ ! -f results/${sample}.vcf.gz ]; then
    lofreq call-parallel --pp-threads $THREADS --verbose --ref data/ref/chrM.fa \
      --out results/${sample}.vcf results/${sample}.bam
    # Compress VCF with samtools (bgzip) and index
    samtools view -Oz -o results/${sample}.vcf.gz results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz
    rm -f results/${sample}.vcf
  fi
done

# Rebuild collapsed.tsv if any VCF is newer than the TSV
rebuild_collapse=0
if [ ! -f results/collapsed.tsv ]; then
  rebuild_collapse=1
else
  for s in "${samples[@]}"; do
    if [ results/${s}.vcf.gz -nt results/collapsed.tsv ]; then
      rebuild_collapse=1
      break
    fi
  done
fi

if [ $rebuild_collapse -eq 1 ]; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for s in "${samples[@]}"; do
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz |
        awk -v sample="${s}" '{print sample"\t"$0}'
    done
  } > results/collapsed.tsv
fi