#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # Align and sort BAM
    [[ -f "results/${sample}.bam" ]] || {
        bwa mem -t 4 data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ 4 -o "results/${sample}.bam"
    }

    # Index BAM
    [[ -f "results/${sample}.bam.bai" ]] || samtools index "results/${sample}.bam"

    # Variant calling with lofreq, compress and index VCF
    [[ -f "results/${sample}.vcf.gz" ]] || {
        lofreq call --vcf -f data/ref/chrM.fa -o "results/${sample}.vcf" "results/${sample}.bam"
        samtools bgzip "results/${sample}.vcf"
        tabix -p vcf "results/${sample}.vcf.gz"
    }
done

# Build collapsed.tsv from all sample VCFs
[[ -f results/collapsed.tsv ]] || {
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%FORMAT/AF]\n' "results/${sample}.vcf.gz" | \
            awk -v s="$sample" '{print s"\t"$0}' >> results/collapsed.tsv
    done
}